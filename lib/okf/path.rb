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
      unless expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
        raise Error, "path escapes bundle root"
      end

      expanded_path
    end
  end
end
