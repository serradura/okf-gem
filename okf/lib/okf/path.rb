# frozen_string_literal: true

module OKF
  module Path
    class Error < OKF::Error
    end

    def self.normalize_relative!(path)
      value = path.to_s
      raise Error, "path is blank" if value.empty?
      raise Error, "path contains null byte" if value.include?("\0")
      raise Error, "path must be relative" if value.start_with?("/")
      raise Error, "path must use forward slashes" if value.include?("\\")

      parts = value.split("/")
      if parts.any? { |part| part.empty? || part == "." || part == ".." }
        raise Error, "path contains unsafe segment"
      end

      parts.join("/")
    end

    def self.join_under!(root, path)
      relative = normalize_relative!(path)
      expanded_root = File.expand_path(root.to_s)
      expanded_path = File.expand_path(File.join(expanded_root, relative))
      raise Error, "path escapes bundle root" unless under?(expanded_root, expanded_path)

      expanded_path
    end

    # Is +path+ the root itself or a descendant of it? Pure string containment
    # (no disk access), so it works on both lexical paths (File.expand_path) and
    # symlink-resolved ones (File.realpath) — the shell resolves, this decides.
    # Both arguments must already be absolute and normalized the same way.
    def self.under?(root, path)
      path == root || path.start_with?("#{root}#{File::SEPARATOR}")
    end
  end
end
