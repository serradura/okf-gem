# frozen_string_literal: true

module OKF
  class Bundle
    # Reads an OKF bundle directory into an in-memory OKF::Bundle. Together with
    # Bundle::Writer this is the only component that touches the filesystem — the
    # core (Bundle, Concept, Graph, Validator, Linter) then works purely in memory.
    #
    # It parses eagerly: each concept file becomes an OKF::Concept, each
    # index.md/log.md is kept as raw text (its structure is validated as text), and
    # a concept file whose frontmatter does not parse is retained as an unparseable
    # entry (carrying the ParseError message, so §9.1 can report it) rather than
    # dropped or raised. Every read goes through Path.join_under! so a
    # symlinked or crafted path cannot escape the bundle root.
    class Reader
      def self.read(dir)
        new(dir).read
      end

      attr_reader :root

      def initialize(dir)
        @root = File.expand_path(dir.to_s)
      end

      def read
        concepts = []
        reserved = []
        unparseable = []

        markdown_paths.each do |path|
          begin
            content = File.read(Path.join_under!(@root, path), encoding: "UTF-8")
            if Concept.reserved?(path)
              reserved << Entry.new(path: path, content: content)
            else
              frontmatter, body = Markdown::Frontmatter.parse(content)
              concepts << Concept.new(path: path, frontmatter: frontmatter, body: body)
            end
          rescue Markdown::Frontmatter::ParseError => e
            unparseable << Entry.new(path: path, content: content, error: e.message)
          end
        end

        Bundle.new(concepts: concepts, reserved: reserved, unparseable: unparseable, root: @root)
      end

      private

      def markdown_paths
        return [] unless Dir.exist?(@root)

        Dir.glob(File.join(@root, "**", "*.md"))
           .select { |path| File.file?(path) }
           .map { |path| Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s }
           .sort
      end
    end
  end
end
