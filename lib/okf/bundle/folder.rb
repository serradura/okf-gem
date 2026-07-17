# frozen_string_literal: true

module OKF
  class Bundle
    # A bundle on disk — the directory-level handle. Reads a directory into a pure
    # OKF::Bundle once, exposes the analyzers over it,
    # and can materialize an in-memory bundle back to disk. Part of the shell.
    #
    #   folder = OKF::Bundle::Folder.load("docs")
    #   folder.bundle             # => OKF::Bundle (pure)
    #   folder.validate; folder.lint; folder.graph
    #   folder.concept("tables/orders")   # => OKF::Concept::File (or nil)
    #
    #   # build in memory (the Rails / snapshot-publisher path) and write it out:
    #   OKF::Bundle::Folder.new(bundle: pure_bundle, root: "out/dir").save
    class Folder
      attr_reader :root, :bundle

      def self.load(dir)
        root = File.expand_path(dir.to_s)
        new(bundle: Reader.read(root), root: root)
      end

      def initialize(bundle:, root:)
        @bundle = bundle
        @root = File.expand_path(root.to_s)
      end

      def concepts
        @bundle.concepts
      end

      def validate
        @bundle.validate
      end

      def lint(**options)
        @bundle.lint(**options)
      end

      def graph(minimal: false, body: true)
        @bundle.graph(minimal: minimal, body: body)
      end

      def catalog
        @bundle.catalog
      end

      def directory_index
        @bundle.directory_index
      end

      # Human-readable "parent/dir" name — the default HTML title.
      # The bundle's display label, "parent/dir" — path arithmetic, no disk. It
      # is a class method so a caller that only wants the label (the registry
      # naming an entry) can have it without a Reader.read of every file.
      def self.label(root)
        pathname = Pathname.new(root)
        "#{pathname.parent.basename}/#{pathname.basename}"
      end

      def name
        self.class.label(@root)
      end

      # A single-file handle for one concept id (read live from disk), or nil when no
      # concept in the loaded bundle has that id. The id may be a frontmatter `id`, so
      # it is resolved to a path through the bundle rather than assumed to be "id.md".
      def concept(id)
        path = @bundle.paths_by_id[id] or return nil
        Concept::File.read(root: @root, path: path)
      end

      # Materialize the in-memory bundle to disk (Writer validates §9 before
      # publishing, so a malformed bundle is never written).
      def save(overwrite: false)
        Writer.call(
          bundle_path: @root,
          concepts: @bundle.concepts,
          index_files: reserved_hash("index.md"),
          log_files: reserved_hash("log.md"),
          overwrite: overwrite
        )
        self
      end

      def reload
        @bundle = Reader.read(@root)
        self
      end

      private

      def reserved_hash(basename)
        @bundle.reserved
               .select { |entry| File.basename(entry.path) == basename }
               .each_with_object({}) { |entry, hash| hash[entry.path] = entry.content }
      end
    end
  end
end
