# frozen_string_literal: true

module OKF
  class Bundle
    # Reads an OKF bundle directory into an in-memory OKF::Bundle. Together with
    # Bundle::Writer this is the only component that touches the filesystem — the
    # core (Bundle, Concept, Graph, Validator, Linter) then works purely in memory.
    #
    # It parses eagerly: each concept file becomes an OKF::Concept, each
    # index.md/log.md is kept as raw text (its structure is validated as text), and
    # a file the reader cannot use — frontmatter that does not parse, or a file it
    # cannot open at all — is retained as an unparseable entry (carrying the
    # ParseError message or the errno, so §9.1 can report it) rather than dropped
    # or raised. That tolerance is the whole §9 best-effort promise: one bad file
    # never breaks the rest, and this is the read every verb shares. Every read
    # goes through Path.join_under! so a symlinked or crafted path cannot escape
    # the bundle root — that guard still raises, because a path leaving the root
    # is not a bad file, it is a bundle lying about its shape.
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
          rescue SystemCallError => e
            # A file that cannot be opened is one unusable file, not a broken
            # bundle. Letting the errno out of here breaks "one bad file never
            # breaks the rest" for every verb at once — the read is the one path
            # they all share — and it breaks it in the worst way: a backtrace,
            # under an exit code that claims the bundle is non-conformant. So it
            # joins the same bucket a bad frontmatter block does, and §9.1 reports
            # it naming the file and the errno.
            #
            # Its content is "" rather than nil: unknown, but every analyzer reads
            # it as text, and empty is the honest shape of a file we never saw —
            # no links to resolve, no encoding to be invalid, nothing claimed.
            unparseable << Entry.new(path: path, content: "", error: e.message)
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
