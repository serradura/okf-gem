# frozen_string_literal: true

module OKF
  module Pro
    # The bundle root plus the edited path made relative to it.
    #
    # `.for` returns nil whenever a check cannot apply — no bundle under the
    # working directory, a path outside it, not markdown, or behind a dot,
    # which is the same boundary `okf` itself walks. A file at the repository
    # root is outside now: README.md and CLAUDE.md are documentation and
    # instructions, not concepts, and no conformance rule reaches them.
    # Nil is a real answer here and not a failure: a check that does not apply
    # has nothing to say, and saying nothing is different from passing something
    # it could not read. The checks distinguish the two.
    class Target
      attr_reader :root, :rel

      def self.for(event)
        # The file's own ancestry decides which bundle governs it — alone.
        # There used to be a cwd fallback here, and it was a fence bypass:
        # containing() would refuse a file inside a nested repository, and
        # resolve(cwd) — which neither walks nor fences — would re-adopt it
        # through the physical-prefix check below whenever the session sat
        # in a root-layout bundle. A file genuinely inside a bundle is
        # found by its own walk — the walk's classifier accepts a
        # versioned index or any core file beside a bare one, so even a
        # mid-bootstrap bundle governs its files; only an index.md truly
        # alone is ambiguous with a directory index, and the walk refuses
        # to guess. The fallback could only ever add adoptions the walk
        # had refused.
        root = BundleRoot.containing(event.file_path)
        return nil if root.nil?

        rel = relative(event.file_path, root)
        return nil if rel.nil? || !rel.end_with?(".md")
        return nil if rel.split("/").any? { |seg| seg.start_with?(".") }

        new(root, rel)
      end

      # Relative to the bundle root, or nil when the path is outside it. Made
      # relative before the dot test on purpose: an absolute path can pass
      # through `/Users/someone/.local/...` and have nothing dot-prefixed about
      # the file itself.
      def self.relative(path, root)
        return nil if path.to_s.empty?

        full = File.expand_path(path)
        full.start_with?("#{root}/") ? full[(root.size + 1)..-1] : nil
      end

      def initialize(root, rel)
        @root = root
        @rel = rel
      end

      # Read once per process. Three PostToolUse checks want the same bundle,
      # and the read is the expensive part — it is the whole reason they arrive
      # as one `post-edit` invocation rather than three.
      def bundle
        @bundle ||= ::OKF::Bundle::Reader.read(root)
      end

      def id
        rel.sub(/\.md\z/, "")
      end

      def basename
        File.basename(rel)
      end

      # A Target holds its root, so every read through it is contained: a
      # `board.md` that is a symlink out of the bundle is not this bundle's
      # board, and the gates must not read it as one.
      #
      # Raises rather than rescuing. A caller asking a Target to read a named
      # core file has already established the file exists (`exist?` above), so
      # a Path::Error here is a real containment failure — and the dispatch
      # rescue in CLI.run turns any exception into a refusal, which is the
      # correct answer to "something outside the bundle is pretending to be
      # inside it".
      def read(name)
        Pro.read_contained(root, File.join(root, name))
      end

      def exist?(name)
        File.exist?(File.join(root, name))
      end
    end
  end
end
