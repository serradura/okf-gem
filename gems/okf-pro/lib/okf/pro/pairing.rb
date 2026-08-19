# frozen_string_literal: true

module OKF
  module Pro
    # The board↔work invariants, in both directions: everything open is on the
    # board, everything the board links is still real, and everything owed is
    # still owed. These are what an editor-made commit bypasses entirely, which
    # is why they are also the CI door's payload.
    #
    # Pairing is by link target, never by substring. The first cut asked
    # `board.include?(slug)`, which a project name mentioned in any unrelated
    # capture line satisfied — a false pass, in the fail-open direction this
    # checker exists to close.
    module Pairing
      module_function

      # `board:` and `concepts:` let a caller that already paid for the read
      # hand it over — the audit reads the board and parses the bundle for
      # its other checks, and a second parse of every concept on the
      # pre-commit hot path buys nothing.
      def failures(root, board: nil, concepts: nil)
        board ||= Pro.read_text(File.join(root, "board.md"))
        targets = board_targets(board)
        concepts ||= ::OKF::Bundle::Reader.read(root).concepts

        unpaired_projects(root, targets) +
          unpaired_briefings(concepts, targets) +
          broken_targets(root, board) +
          closed_project_links(root, board) +
          stale_read_lines(concepts, board)
      end

      # Forward: every open project is linked from some board line.
      def unpaired_projects(root, targets)
        open_projects(root).map do |name|
          prefix = "/projects/#{name.downcase}"
          next if targets.any? { |t| t == prefix || t.start_with?("#{prefix}/") }

          "— pairing: projects/#{name} has no board line and no closed marker."
        end.compact
      end

      # Forward: every generated-without-verified briefing is linked from some
      # board line — the To-read line it was born paired with, or the conflict
      # line that is also a claim on attention.
      def unpaired_briefings(concepts, targets)
        unverified_ids(concepts).map do |id|
          next if targets.include?("/#{id}.md".downcase)

          "— pairing: unverified briefing #{id}.md has no read-owed board line — " \
            "it silently left the attention system."
        end.compact
      end

      # Reverse: every bundle link the board carries lands on something real.
      # `okf lint` checks links inside concepts, but the board's capture lines
      # use the bare `[/path]` form lint never parses — rot here is invisible
      # to everything but this.
      def broken_targets(root, board)
        entries = bundle_entries(root)
        board_lines(board).flat_map do |line|
          Board.targets(line).map do |target|
            next if entries.include?(target.downcase.chomp("/"))

            "— pairing: board line links #{target}, which does not exist in the bundle."
          end.compact
        end
      end

      # Reverse: closure removes board lines wholesale, so a line still linking
      # a closed project is the ritual left half-done.
      def closed_project_links(root, board)
        closed = closed_projects(root)
        return [] if closed.empty?

        board_lines(board).flat_map do |line|
          Board.targets(line).map do |target|
            slug = target[%r{\A/projects/([^/\s]+)}i, 1]
            next unless slug && closed.include?(slug.downcase)

            "— pairing: board line still links projects/#{slug}, which is closed — " \
              "closure removes its board lines."
          end.compact
        end
      end

      # Reverse: a read-owed line whose briefing is already verified. Reading
      # is the one event that removes the line, and it happened. A To-read line
      # with no bundle link at all is fine — documents live outside bundles too,
      # and the check speaks only about what it can see.
      def stale_read_lines(concepts, board)
        verified = verified_reference_targets(concepts)
        Board.section_lines(board, "To read").flat_map do |line|
          Board.targets(line).map do |target|
            next unless verified.include?(target.downcase)

            "— pairing: read-owed line links #{target}, which is already verified — " \
              "reading removes the line, and the reading happened."
          end.compact
        end
      end

      # Visible lines only — a commented-out sample line must not be a
      # pairing target or a broken-link finding, for the same reason the
      # counters do not count it.
      def board_lines(board)
        Board.visible(board).each_line.select { |l| l.start_with?("- ") }
      end

      def board_targets(board)
        board_lines(board).flat_map { |l| Board.targets(l) }.map(&:downcase)
      end

      # Downcased so pairing behaves the same on a case-sensitive filesystem
      # as on the case-insensitive one the bundle was probably written on.
      def bundle_entries(root)
        Dir.glob(File.join(root, "**", "*"))
           .map { |p| "/#{p[(root.size + 1)..-1]}".downcase.chomp("/") }
      end

      def open_projects(root)
        project_dirs(root).map do |dir|
          File.basename(dir) unless closed?(root, File.join(dir, "index.md"))
        end.compact
      end

      def closed_projects(root)
        project_dirs(root).map do |dir|
          File.basename(dir).downcase if closed?(root, File.join(dir, "index.md"))
        end.compact
      end

      def project_dirs(root)
        Dir.glob(File.join(root, "projects", "*", "")).sort
      end

      # Closure is one marker, matched as one pattern: the word "closed" —
      # not hyphen-joined into a name — then its date, with only marker
      # punctuation between, read across the top of the index (three lines,
      # the old tolerance), never the body. Every weaker reading failed in
      # practice: bare /closed/i made titles and verbs into closures;
      # word-plus-date-anywhere closed dated titles; a forty-character gap
      # admitted prose; whitelisting "on" re-admitted "The office closed on
      # 2026-01-05"; and an unguarded comma admitted "we closed, 2026-01-05,
      # the books". The accepted spellings are enumerated ONCE, in the
      # skill's closing ritual; MARKER is that enumeration, and the grammar
      # tests pin both lists to each other.
      MARKER = /\bclosed\b(?!-)[[:blank:]*(\u2014\u2013:-]*\d{4}-\d{2}-\d{2}/i.freeze

      # A negation must not close the thing it denies. This is a blacklist
      # of negators, and honestly so — a two-literal lookbehind briefly
      # posed as "not negated" while "**not** closed", a double space, or
      # "wasn't" walked straight past it. Markup and punctuation may sit
      # between the negator and the verb, exactly as they may sit between
      # the verb and its date.
      NEGATED = /\b(?:not|never|no longer|isn['\u2019]?t|wasn['\u2019]?t|hasn['\u2019]?t)[\W_]*closed\b/i.freeze

      def marker?(line)
        line.match?(MARKER) && !line.match?(NEGATED)
      end

      # Read through the kernel's containment primitive rather than File.read:
      # this holds a root, and `SafeRead.read!` resolves the path and refuses
      # one whose symlinks escape it. Byte-identical output for every real
      # file — the `.scrub` is still this gem's, because `read!` tags the
      # encoding without validating it and one invalid byte anywhere raises out
      # of the first regex, which the hook protocol reads as non-blocking.
      #
      # NOT applied at `BundleRoot.root_index?`, which has no root to contain
      # against — it is deciding what the root is — and where a raise would be a
      # permanent lockout and a rescue would answer "not a root", mis-rooting
      # the bundle and disarming the journal guard.
      # Contained against the BUNDLE root, which every caller already holds.
      # Deriving it as `dirname(dirname(index_path))` gave `<bundle>/projects`,
      # so `SafeRead` refused any project index whose realpath left `projects/`
      # — including one that never leaves the bundle. A project legitimately
      # archived behind a symlink (`projects/beta -> ../archive/beta`) read as
      # open forever, and the audit demanded a board line for work closed
      # months ago. The containment rule is about the bundle, and a root
      # invented from the path being checked is not the bundle.
      def closed?(root, index_path)
        return false unless File.exist?(index_path)

        Pro.read_contained(root, index_path).lines.first(3).any? { |line| marker?(line) }
      rescue ::OKF::Path::Error, ::Errno::ENOENT
        # A project index reached only through a symlink out of the bundle is
        # not a closure marker anyone may rely on. Open is the safe answer: an
        # open project keeps its board line, a closed one loses it.
        false
      end

      # ── the read-owed rule, in the kernel's vocabulary ─────────────────────
      #
      # These two are exact opposites and MUST stay so, or a briefing falls
      # through both: `unverified_ids` says "the board still owes this a To-read
      # line", `verified_reference_targets` says "the line can go". They are
      # read by `unpaired_briefings` and `stale_read_lines` respectively, plus
      # `Attestation.report` and the snapshot counter — four call sites, one
      # rule, and the rule is:
      #
      #   a briefing is owed a read until a HUMAN has verified it.
      #
      # `okf` 2.0 answers that directly. `declared_generated?` is raw-key
      # detection, so it distinguishes hand-written (no provenance at all) from
      # v0.1-with-a-timestamp, which the old `frontmatter["generated"]` test
      # conflated with the fallback. And `trust_tier` reads §5.3: no `verified`
      # is unverified, a `process:` or agent actor is machine-confirmed, a
      # `human:<id>` actor is human-reviewed.
      #
      # The tier is what makes these opposites rather than merely different.
      # Testing `frontmatter["verified"]` for truthiness made a nightly
      # `process:`-verified briefing simultaneously *awaiting the owner's read*
      # to one caller and *verified, drop the line* to the other — the board
      # line vanished and the read was never owed to anyone again. Moving one
      # site and not the other manufactures exactly that state, which is why
      # this comment sits over both of them.
      def awaiting_read?(concept)
        concept.declared_generated? && concept.trust_tier != :human_reviewed
      end

      def owner_read?(concept)
        concept.trust_tier == :human_reviewed
      end

      def briefing?(concept)
        concept.id.start_with?("reference/")
      end

      def unverified_ids(concepts)
        concepts.map do |concept|
          next unless briefing?(concept)
          next unless awaiting_read?(concept)

          concept.id
        end.compact
      end

      def verified_reference_targets(concepts)
        concepts.map do |concept|
          next unless briefing?(concept)
          next unless owner_read?(concept)

          "/#{concept.id}.md".downcase
        end.compact
      end

      # The one shell-out in the whole checker. `--` plus the pathspec keeps it
      # to markdown, so a change confined to hooks or CI does not summon Rule 2's
      # end-of-day questions.
      def dirty_markdown?(root)
        out = IO.popen(
          [ "git", "-C", root, "status", "--porcelain", "--", "*.md" ],
          err: File::NULL, &:read
        )
        # Only a git that ran and answered may disengage the gate. A git that
        # failed — dubious ownership, a corrupted .git, a root outside any
        # repository — is not "no work happened"; it is "nobody can tell",
        # and a gate that cannot tell must not wave the session through.
        # Returning false here was the silent-disarm hole: stderr was nulled,
        # the empty read looked clean, and the stop gate asked no questions.
        return true unless $?.success?

        !out.to_s.strip.empty?
      rescue Errno::ENOENT
        # No git at all is the same state as a failing one — nobody can tell
        # whether work happened — and gets the same answer.
        true
      end
    end
  end
end
