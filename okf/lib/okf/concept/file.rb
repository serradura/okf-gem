# frozen_string_literal: true

module OKF
  class Concept
    # A single concept file on disk — the ActiveRecord-style handle over one `.md`.
    # Wraps a pure OKF::Concept with load/save/delete/reload side effects. Part of
    # the shell (it does I/O); the pure Concept knows nothing about it.
    #
    #   file = OKF::Concept::File.read(root: "docs", path: "tables/orders.md")
    #   file.concept              # => OKF::Concept (pure)
    #   file.concept.links        # interrogate it in memory
    #   file.save                 # write concept.to_markdown back to disk
    #   file.delete
    #
    # NOTE: this class is named File, which shadows Ruby's File inside the
    # OKF::Concept namespace — every filesystem call here uses ::File explicitly.
    #
    # absolute_path guards the *name* lexically (Path.join_under!), which is all a
    # write needs — the file may not exist yet. A read has more to prove: the file
    # is on disk now, so it may be a symlink whose name is inside the root but
    # whose target is not, and File.expand_path does not resolve links. So #reload
    # realpath-resolves before reading and refuses a target outside the root,
    # closing the same escape Bundle::Reader closes on the bulk read.
    class File
      attr_reader :root, :path, :concept

      # Read a concept file from disk into a handle.
      def self.read(root:, path:)
        new(root: root, path: path).reload
      end

      # Write a concept's markdown to disk under +root+ and return the handle.
      def self.write(root:, concept:)
        new(root: root, path: concept.path, concept: concept).save
      end

      def initialize(root:, path:, concept: nil)
        @root = ::File.expand_path(root.to_s)
        @path = Path.normalize_relative!(path)
        @concept = concept
      end

      # Absolute on-disk path, guarded so it cannot escape the bundle root.
      def absolute_path
        Path.join_under!(@root, @path)
      end

      def save
        raise Error, "no concept to save" if @concept.nil?

        target = absolute_path
        ::FileUtils.mkdir_p(::File.dirname(target))
        ::File.write(target, @concept.to_markdown, encoding: "UTF-8")
        self
      end

      def delete
        ::FileUtils.rm_f(absolute_path)
        self
      end

      def reload
        content = ::File.read(contained_read_path, encoding: "UTF-8")
        frontmatter, body = Markdown::Frontmatter.parse(content)
        @concept = Concept.new(path: @path, frontmatter: frontmatter, body: body)
        self
      end

      # The on-disk path to read, refused if the resolved target escapes the root
      # by symlink. Kept separate from #absolute_path because writes join a path
      # that need not exist yet, while a read can and must resolve the real file.
      def contained_read_path
        target = absolute_path
        raise Path::Error, "symlink target escapes bundle root" unless Path.under?(::File.realpath(@root), ::File.realpath(target))

        target
      end
      private :contained_read_path
    end
  end
end
