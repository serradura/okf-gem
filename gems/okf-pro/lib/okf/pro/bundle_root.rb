# frozen_string_literal: true

module OKF
  module Pro
    # Where the bundle is, given where the agent is.
    #
    # The hook event carries a working directory, which is the repository root
    # — not the bundle. They stopped being the same thing when the knowledge
    # moved into `.okf/` and the repository kept README, CLAUDE.md, the
    # checker and CI at the top. Every check that reads the corpus has to make
    # that hop, and making it in one place is the difference between one rule
    # and six copies of it drifting apart.
    #
    # Both layouts resolve, nested first. An adopter who prefers the repository
    # root to *be* the bundle — the shape this template shipped with — is not
    # broken by the change, and neither are the fixtures.
    module BundleRoot
      DIR = ".okf"

      module_function

      # The bundle root, or nil when `start` is not a repository holding one.
      # Nil is a real answer: a check that cannot find a bundle has nothing to
      # say about it, which is different from finding one and approving of it.
      def resolve(start)
        base = File.expand_path(start.to_s)

        nested = File.join(base, DIR)
        return nested if bundle?(nested)
        return base if bundle?(base)

        nil
      end

      # The bundle that contains `path`, found by walking up from the file
      # itself — or nil. The discriminator is level_root/root_kind below:
      # the innermost strong or anchored root wins outright, and plain weak
      # candidates resolve by fencing, so journal/index.md and friends do
      # not stop the walk. This exists because scoping trust
      # guards through the event's cwd was a hole: cwd is wherever the
      # session happens to sit, resolve() never walks up, and a session
      # parked in a subdirectory made the guards find no bundle and
      # silently disarm.
      # Fenced at the file's own repository, exactly as enclosing() is: a
      # bundle above the session's repo is somebody else's, and a file
      # inside a nested repository must not summon the guards of the tree
      # above it. Outside any repository the walk runs to the filesystem
      # root — a file physically inside a bundle's tree is governed by it,
      # which is the walk's whole claim; the directory walk cannot say the
      # same of a cwd, which is why enclosing() refuses to walk unfenced.
      #
      # ONE deliberate divergence from enclosing(): `probe_nested: false`.
      # A root that does not contain the file is no root of it, so this
      # walk never adopts a sibling `.okf`. In the one layout where that
      # matters — a directory that is BOTH a flat root and the parent of
      # an `.okf` root — this door governs a file outside `.okf` by the
      # flat root while the stop gate and the audit govern `.okf`. That
      # layout is ambiguous at its source (two bundles, one directory),
      # the alternative was guards that skipped the file in silence, and
      # Audit.ambiguous_layout reports it rather than leaving the doors to
      # disagree quietly.
      def containing(path)
        return nil if path.to_s.empty?

        dir = File.dirname(File.expand_path(path))
        top = repo_root(dir)
        weak = nil
        until dir == File.dirname(dir)
          kind, found = level_root(dir, probe_nested: false)
          case kind
          when :strong, :anchored
            return found
          when :weak
            # Fenced, the outermost weak directory inside the fence is the
            # bundle — a real root contains its directories. Unfenced there
            # is no "outermost inside" to speak of, and climbing toward the
            # filesystem root adopted a stranger's index+log over the
            # bundle the file actually lives in — so the nearest weak root
            # wins and the walk stops guessing upward.
            return found if top.nil?

            weak = found
          end
          break if dir == top

          dir = File.dirname(dir)
        end
        weak
      end

      # The bundle governing a working directory, found by walking up from
      # it. Same classifier, same tiers as containing(); the only
      # difference is the no-repository rule — a cwd, unlike a file, is
      # not "inside" anything in a way that justifies climbing, so with no
      # fence the look is single-level and cannot adopt anything above the
      # directory it was handed.
      def enclosing(start)
        dir = File.expand_path(start.to_s)
        top = repo_root(dir)
        if top.nil?
          kind, found = level_root(dir)
          return kind ? found : nil
        end

        weak = nil
        loop do
          kind, found = level_root(dir)
          case kind
          when :strong, :anchored
            return found
          when :weak
            weak = found
          end
          break if dir == top

          dir = File.dirname(dir)
        end
        weak
      end

      # The first ancestor (inclusive) holding a .git entry — a directory
      # for ordinary repositories, a file for worktrees and submodules.
      def repo_root(dir)
        until dir == File.dirname(dir)
          return dir if File.exist?(File.join(dir, ".git"))

          dir = File.dirname(dir)
        end
        nil
      end

      # The strongest proof at one level, ONCE — both walks consume this,
      # so the ordering cannot drift between them (it did, and the doors
      # governed different bundles). `probe_nested:` is the walks' one
      # legitimate difference: enclosing roots a CWD, and the bundle
      # governing a session may sit beside it at any ancestor level, so
      # each level's `.okf` is probed. containing roots a FILE, and a
      # root that does not contain the file is no root of it — the
      # sibling probe adopted repo/.okf for repo/reference/x.md, the rel
      # path nil'd out, and every write-time guard skipped the edit in
      # silence. A file actually inside `.okf` meets it as the dir itself
      # on the way up, so containing loses nothing by not probing.
      # Three tiers, nested .okf (when probed) before the level itself:
      #   :strong   — okf_version in the index frontmatter. Innermost wins,
      #               immediately: only a root carries it.
      #   :anchored — a weak proof in a directory literally named `.okf`.
      #               The name is the convention's own marker, so an inner
      #               nested bundle beats outer coincidence — outer-weak-
      #               wins let a stray index+log at the repo root shadow a
      #               real frontmatterless .okf and silently disarm every
      #               write-time guard.
      #   :weak     — index.md plus any core file (board.md or log.md) in
      #               an ordinarily named directory. Resolution differs by
      #               fencing; see the walks.
      def level_root(dir, probe_nested: true)
        nested = File.join(dir, DIR)
        nested_kind = probe_nested ? root_kind(nested) : nil
        return [ :strong, nested ] if nested_kind == :strong

        dir_kind = root_kind(dir)
        return [ :strong, dir ] if dir_kind == :strong
        return [ :anchored, nested ] if nested_kind == :weak

        case dir_kind
        when :weak
          File.basename(dir) == DIR ? [ :anchored, dir ] : [ :weak, dir ]
        end
      end

      # One stat ladder per directory: :strong, :weak, or nil. The weak
      # proof accepts ONE core file, not the whole skeleton — demanding
      # both left a mid-bootstrap bundle (index and board down, log.md not
      # yet written) unguarded while its first concepts landed. An
      # index.md truly alone remains ambiguous with a directory index and
      # is never adopted: the scaffold writes the skeleton in one move,
      # and a walk that guessed would re-open the bogus-adoption hole.
      def root_kind(dir)
        return nil unless File.file?(File.join(dir, "index.md"))
        return :strong if root_index?(dir)

        return unless File.file?(File.join(dir, "board.md")) || File.file?(File.join(dir, "log.md"))

        :weak
      end

      def bundle?(dir)
        File.file?(File.join(dir, "index.md"))
      end

      # A fence exactly as the okf gem parses one — dashes at column zero,
      # trailing blanks tolerated, nothing else. One rule, not two that
      # drift: strip-based matching briefly accepted indented fences here,
      # which ended the scan at a "---" inside a YAML block scalar (real
      # root unrecognised, guards re-rooted through the cwd fallback) and
      # recognised roots the gem itself refuses to parse. No BOM tolerance
      # for the same reason — the gem raises on one, and a "root" whose
      # corpus every later check crashes on is not a root.
      FENCE = /\A---[[:blank:]]*\z/.freeze

      # The root index declares `okf_version:` in its frontmatter. Matching
      # the bare token anywhere in the file was a hole: directory indexes are
      # free-form prose, this bundle is *about* OKF, and a journal index that
      # mentioned okf_version in a sentence would have stopped the walk early,
      # mis-rooted the bundle, and disarmed the journal guard through a rel
      # path that no longer started with journal/. Only the key, only inside
      # a COMPLETE leading frontmatter block, counts — the closing fence is
      # required, because a mangled block that never closes must not let a
      # column-zero mention in prose adopt the directory. The block is read
      # once (no re-enumeration racing an agent's write between two opens)
      # through Pro.read_text, and bounded: frontmatter whose closing fence
      # sits past line 101 is not recognised, a stated limit rather than a
      # silent one, and pinned by a test.
      def root_index?(dir)
        index = File.join(dir, "index.md")
        return false unless File.file?(index)

        # Streamed, not slurped: this runs per ancestor on every tool-use
        # event, and read_text pulled the whole file in before the 101-line
        # bound was applied. The per-line scrub matches read_text's
        # defense — bytes in, forced UTF-8, invalid sequences replaced.
        lines = []
        File.foreach(index, mode: "rb") do |l|
          lines << l.force_encoding(Encoding::UTF_8).scrub.chomp
          break if lines.size >= 101
        end
        return false unless lines.first&.match?(FENCE)

        body = lines.drop(1)
        close = body.index { |l| l.match?(FENCE) }
        return false if close.nil?

        body.first(close).any? { |l| l.match?(/\Aokf_version[[:blank:]]*:/) }
      rescue Errno::ENOENT
        # The file passed File.file? and vanished before the read — an agent
        # write or checkout mid-hook. Not a root anybody can prove; keep
        # walking.
        false
      end
    end
  end
end
