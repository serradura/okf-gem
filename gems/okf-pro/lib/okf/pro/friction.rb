# frozen_string_literal: true

require "fileutils"

module OKF
  module Pro
    # What the verbs did not cover — recorded, never enforced.
    #
    # Every verb in this gem is a gate or a report. This one is neither: it
    # writes down the moments an agent did by hand something a command could
    # have done, so the question "which verb is missing?" is answered by
    # evidence instead of by the maintainer's imagination. Two points feed it,
    # and both are code paths that already run — no new hook event, because
    # `settings.json` is SEEDED and a new registration would never reach an
    # adopter through `upgrade`.
    #
    # It records INTENT, not outcome. `shell-guard` fires at PreToolUse, before
    # the owner may deny, so a recorded line means "this was attempted by
    # hand", which is exactly the question being asked.
    #
    # THE THIRD CLAUSE, APPLIED TO TELEMETRY. This is not a check: it neither
    # refuses nor blocks, and a recorder that crashed a gate would be a
    # measurement worth less than the thing it measures. But it does not lie
    # about having counted. A write that fails leaves a marker beside the log,
    # and an unwritable scratch directory is the same state — both make
    # `report` answer `available == false`, and the banner says the data is
    # unavailable rather than printing a zero nobody can distinguish from a
    # session that used the verbs.
    module Friction
      # The scratch directory the seeded `.gitignore` already ignores, at the
      # REPOSITORY root rather than inside the bundle: this is telemetry about
      # the bundle, not knowledge in it, and `okf validate` walks every `.md`
      # under the root.
      SCRATCH = ".tmp"
      LOG = "okf-pro-friction.log"
      MARKER = "okf-pro-friction.unavailable"

      # What `report` hands back. `available` is the honest half: false means
      # the count is not zero, it is unknown.
      # `events`, not `entries`: a Struct member of that name overrides
      # `Struct#entries` — Enumerable's alias for `to_a` — and a reader that
      # got the Struct's own fields back instead of the recorded lines would
      # be a silently wrong count, which is the one thing this must not be.
      Report = Struct.new(:events, :unreadable, :available)

      module_function

      # The repository the bundle sits in. `.okf/board.md` is a bundle under a
      # repository; a flat root IS the repository. Nothing else distinguishes
      # them, and the scratch directory belongs to the outer one either way.
      def scratch_root(root)
        base = File.expand_path(root.to_s)
        File.basename(base) == BundleRoot::DIR ? File.dirname(base) : base
      end

      def log_path(root)
        File.join(scratch_root(root), SCRATCH, LOG)
      end

      def marker_path(root)
        File.join(scratch_root(root), SCRATCH, MARKER)
      end

      # One line appended, or a marker set. Never raises: the callers are a
      # PreToolUse guard and a PostToolUse check, and an exception out of
      # either is an edit sailing through while the gate lies on the floor.
      def record(root, via, what, detail = nil, today: Date.today)
        path = log_path(root)
        FileUtils.mkdir_p(File.dirname(path))
        entry = { "at" => today.to_s, "via" => via, "what" => what }
        entry["detail"] = detail if detail
        File.open(path, "a") { |file| file.puts JSON.generate(entry) }
        true
      rescue StandardError
        mark_unavailable(root)
        false
      end

      def mark_unavailable(root)
        path = marker_path(root)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") { |file| file.puts Date.today.to_s }
        nil
      rescue StandardError
        # Nothing left to try. `report` reaches the same verdict from the
        # unwritable directory itself, which is why this may give up quietly.
        nil
      end

      # Entries in file order, plus the two things a reader must not be told
      # by omission: how many lines would not parse, and whether the recorder
      # was able to run at all.
      def report(root)
        events = []
        unreadable = 0
        path = log_path(root)
        if File.exist?(path)
          Pro.read_text(path).each_line do |line|
            next if line.strip.empty?

            parsed = parse(line)
            parsed ? events << parsed : unreadable += 1
          end
        end
        Report.new(events, unreadable, available?(root))
      rescue StandardError
        Report.new([], 0, false)
      end

      def parse(line)
        value = JSON.parse(line)
        value.is_a?(Hash) ? value : nil
      rescue JSON::ParserError
        nil
      end

      # Writable, and never marked. An unwritable scratch directory has
      # recorded nothing and cannot say so in a marker either, so it is asked
      # directly rather than inferred from an empty log.
      def available?(root)
        return false if File.exist?(marker_path(root))

        dir = File.join(scratch_root(root), SCRATCH)
        return File.writable?(dir) if File.directory?(dir)
        # Something is there and it is not a directory, so `mkdir_p` will raise
        # every time and the marker cannot be written either — which is the
        # case that proves the marker alone is not enough to answer this.
        return false if File.exist?(dir)

        File.writable?(scratch_root(root))
      rescue StandardError
        false
      end

      # The good path must not count as friction, or the recorder reports the
      # verbs being used as evidence that they are not.
      #
      # Anchored to the START of the segment, because the question is "is this
      # an invocation of the gem?" and not "is the gem mentioned?". Matched
      # anywhere, a board line's own TEXT excused the hand-write that appended
      # it — `echo "- see okf pro docs" >> .okf/board.md` was never recorded,
      # and board lines routinely name these verbs. `ShellGuard.own_write?`
      # does the splitting; this is asked of one segment.
      #
      # An assignment prefix is part of the invocation and not a command of its
      # own, so it is skipped rather than breaking the anchor: `$OKF_HOME` is a
      # variable this ecosystem actually uses, and `OKF_HOME=/tmp okf pro
      # snapshot >> .okf/log.md` is the prescribed move with a prefix on it.
      #
      # So is a wrapper, and the list is short and named rather than open:
      # `bundle exec okf pro snapshot >> .okf/log.md` is *this repo's own*
      # invocation of the prescribed move, and an anchor that missed it counted
      # a contributor's first command as friction. An open rule would be a way
      # back to matching a mention.
      WRAPPERS = /(?:bundle\s+exec|env|time|nice|nohup|sudo|command)\s+/.freeze
      OWN_COMMAND = /\A\s*(?:[A-Za-z_]\w*=\S*\s+)*(?:#{WRAPPERS})*okf\s+pro\b/.freeze

      def own_command?(command)
        command.to_s.match?(OWN_COMMAND)
      end

      # The board, and ONLY the board.
      #
      # The obvious wider list — board, log, journal day — was wrong in the
      # direction that destroys the measurement: it counted the PRESCRIBED path
      # as friction. `snapshot` deliberately has no `--write`, so appending the
      # Snapshot line to `log.md` by hand is exactly what this gem tells you to
      # do; `journal open` says in as many words that the day's content is
      # yours to write. Recording either inflates the banner's request and
      # points the maintainer at verbs that already exist and already declined
      # to do that job — which is the same mistake `own_command?` exists to
      # prevent, made one layer up.
      #
      # An Edit to a concept body is judgment and always will be. What is left
      # is `board.md`: a shape with exactly one correct form, edited by hand
      # while three verbs cover it.
      # The path is bundle-relative, so this is an equality rather than a
      # basename test: `projects/x/board.md` is somebody's notes, not the one
      # page Rule 3 counts, and the verbs do not touch it.
      #
      # One covered path also means the class a row records as IS the path, so
      # the call site passes it straight through. The `classify` that used to
      # fold three paths into three classes had two answers nothing could reach
      # from this door, and a unit test calling it directly kept them green.
      def covered_path?(rel)
        rel.to_s == "board.md"
      end

      # The two answers `covered_by` can give, as constants — so a reader may be
      # COMPARED against one instead of pattern-matched. `verb_covered?` below
      # asks a narrower question than `covered_by` answers, and a prefix test on
      # the prose would have coupled it to wording nobody would think to
      # preserve.
      SHELL_ANSWER = "Edit or Write — the trust guards read a tool event, and a shell redirect is none"
      BOARD_ANSWER = "okf pro capture / promote / demote"

      # What a recorded row maps to, where something already covers it — so the
      # report says "this is a verb now" rather than making the reader guess,
      # and phase 3's question keeps being answered after phase 3.
      #
      # Keyed on `via` as well as `what`, because the two doors mean different
      # things about the same file. An Edit to the board is a verb's job. A
      # SHELL write is a bypass whatever it touched — the trust guards read a
      # tool event and a redirect produces none — so what covers it is Edit or
      # Write, not an `okf pro` verb.
      def covered_by(via, what)
        return SHELL_ANSWER if via == "shell"
        return BOARD_ANSWER if what == "board.md"

        nil
      end

      # Whether an `okf pro` VERB covers it — which is not the same question as
      # whether anything does. A shell redirect at the board is covered, by Edit
      # or Write, and there is no verb to ask for; a banner counting it told the
      # adopter a verb could have done something no verb does.
      def verb_covered?(via, what)
        answer = covered_by(via, what)
        !answer.nil? && answer != SHELL_ANSWER
      end

      # Everything the log holds, cleared — the log itself and the marker.
      #
      # The marker is deliberately sticky: one failed write means the count is
      # short by an unknown amount forever after, and a recorder that quietly
      # forgave itself would be back to reporting a zero it did not count. But
      # sticky with no way out is a report that nags permanently about a full
      # disk from three weeks ago, so the way out is explicit, named in the
      # message, and belongs to the reader.
      def clear(root)
        [ log_path(root), marker_path(root) ].count do |path|
          next false unless File.exist?(path)

          File.unlink(path)
          true
        end
      rescue StandardError
        nil
      end

      # The covered classes, read out of a shell COMMAND instead of a path. A
      # command has no `file_path` — that is the whole reason `shell-guard`
      # exists — so this reads the names it mentions, and answers "unclassified"
      # when it cannot tell. That is not a failure: the report's question is which
      # verb is missing, and a write it cannot attribute is exactly the row that
      # says "we do not know yet".
      #
      # Wider than `covered_path?`, deliberately, and the two doors are asking
      # different questions: the edit door asks "is this a shape a verb covers?",
      # and a redirect is a bypass whatever it touched. `journal` collapses a year
      # of days into one row rather than three hundred.
      def classify_command(command)
        text = command.to_s
        return "board.md" if text.include?("board.md")
        return "log.md" if text.include?("log.md")
        return "journal" if text.match?(%r{journal/\d{4}-\d{2}-\d{2}\.md})

        "unclassified"
      end
    end
  end
end
