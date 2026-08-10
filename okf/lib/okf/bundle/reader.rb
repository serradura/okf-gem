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
    # never breaks the rest, and this is the read every verb shares.
    #
    # Containment is enforced twice, because the two ways out of the root are
    # different. A crafted *path* (`..`, an absolute string) is caught lexically
    # by Path.join_under!. A *symlink* whose name sits inside the root but whose
    # target does not cannot be seen lexically — File.expand_path does not
    # resolve links — so each file is also realpath-resolved and its real
    # location checked against the real root before a byte is read. An escaping
    # file joins the unparseable bucket rather than raising: a planted symlink is
    # one bad file, and letting it take down the whole bundle read would hand any
    # writer of a served directory a denial of service. §9.1 then names it.
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

        paths = markdown_paths
        # Resolved once for the whole loop, but never at the cost of the
        # best-effort promise: if the root itself has become unreadable since
        # the glob, this stays nil and each file's own SafeRead call raises
        # inside the per-file rescue below — one bad bundle degrades to
        # unparseable entries, it does not crash the read every verb shares.
        real_root = begin
          File.realpath(@root) unless paths.empty?
        rescue SystemCallError
          nil
        end

        paths.each do |path|
          begin
            absolute = Path.join_under!(@root, path)
            content = SafeRead.read!(@root, absolute, real_root: real_root)
            if Concept.reserved?(path)
              reserved << Entry.new(path: path, content: content)
            else
              frontmatter, body = Markdown::Frontmatter.parse(content)
              concepts << Concept.new(path: path, frontmatter: frontmatter, body: body)
            end
          rescue Markdown::Frontmatter::ParseError => e
            unparseable << Entry.new(path: path, content: content, error: e.message)
          rescue Path::Error, SystemCallError => e
            # A file we cannot safely read is one unusable file, not a broken
            # bundle: an errno on open, or a path that leaves the root — lexically
            # (`..`, an absolute string) or through a symlink whose target escapes
            # it. Letting either out of here breaks "one bad file never breaks the
            # rest" for every verb at once — the read is the one path they all
            # share — and in the worst way: a backtrace under an exit code that
            # claims non-conformance, or a served bundle taken down by one planted
            # symlink. So it joins the same bucket a bad frontmatter block does,
            # and §9.1 reports it naming the file and the reason.
            #
            # Its content is "" rather than nil: unknown, but every analyzer reads
            # it as text, and empty is the honest shape of a file we never read —
            # no links to resolve, nothing claimed, and for a symlink escape, none
            # of the target's bytes.
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
