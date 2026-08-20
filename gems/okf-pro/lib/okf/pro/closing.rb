# frozen_string_literal: true

module OKF
  module Pro
    # Rule 2 — the day ends with a snapshot, and the delta is the signal.
    #
    # One of these refuses and one only informs, and that asymmetry is the rule
    # itself: the snapshot is written at the end (stop-gate refuses without it,
    # and refuses one that disagrees with the board), and read at the beginning
    # (session-context puts yesterday's line in front of you before anything
    # else). A counter nobody compares is wallpaper.
    #
    # Both root through BundleRoot.enclosing — the ancestor walk — because
    # their only input is the session's cwd, and a session parked in a bundle
    # subdirectory must not be a session whose stop gate silently disengaged
    # or mistook a directory index for a broken core. resolve() does neither
    # walk nor discriminate, and was both of those bugs at once.
    module Closing
      module_function

      def stop_gate(event, today: Date.today)
        return [] if event.stop_hook_active?

        root = BundleRoot.enclosing(event.cwd)
        return [] if root.nil?

        # The precondition is "work happened". A session that read and changed
        # nothing owes no snapshot, and asking for one would train people to
        # write a line that means nothing.
        return [] unless Pairing.dirty_markdown?(root)

        # A bundle missing its skeleton used to slip this gate in silence —
        # no board, no log, no questions asked. Broken core is the first
        # refusal, and the only one, because every later check reads the core.
        broken = Audit.structure(root)
        return [ "RULE 2 — before stopping:\n#{broken.map { |m| "— #{m}" }.join("\n")}" ] unless broken.empty?

        # One read of the board, one parse of the bundle, shared by every
        # check below — this gate runs on every Stop, and it used to pay for
        # both twice.
        board = Pro.read_text(File.join(root, "board.md"))
        concepts = ::OKF::Bundle::Reader.read(root).concepts

        msgs = []
        snap = Log.snapshot_line(Pro.read_text(File.join(root, "log.md")), today.to_s)
        if snap.nil?
          msgs << "— log.md has no Snapshot line under #{today}. Append it before stopping — " \
                  "computed from the bundle as it stands:\n  #{Snapshot.line(root, today: today, board: board, concepts: concepts)}"
        else
          # Presence was never the point; agreement is. This runs at stop time,
          # which is the one moment the calendar cannot make it lie — the same
          # check in CI would fail on a push nobody made that day.
          msgs.concat(Snapshot.verify(root, snap, today: today, board: board, concepts: concepts))
        end
        # A dated line the counters cannot parse counts as zero, and a zero
        # is indistinguishable from a quiet board — so the snapshot the gate
        # just verified would agree with itself about a deadline it cannot
        # see. The unreadable line is a refusal, not a rounding error.
        msgs.concat(Board.grammar(board).map { |m| "— board: #{m}" })
        msgs.concat(Pairing.failures(root, board: board, concepts: concepts))
        return [] if msgs.empty?

        [ "RULE 2 — before stopping:\n#{msgs.join("\n")}" ]
      end

      def session_context(event, today: Date.today)
        root = BundleRoot.enclosing(event.cwd)
        return nil if root.nil?

        # This channel cannot refuse, so a broken core is said out loud rather
        # than shown as a suspiciously quiet banner.
        broken = Audit.structure(root)
        unless broken.empty?
          return [ "Bundle at #{root} has a broken core:",
                   *broken.map { |m| "  — #{m}" },
                   "The gates cannot read a bundle missing its skeleton; restore it, then `okf pro audit .`." ]
        end

        lines = state_block(State.call(root, today: today), today)
        lines.concat(Budget.dormancy_questions(root, today: today,
          board: Pro.read_text(File.join(root, "board.md"))))
        lines << REFRESH
        lines.concat(friction_line(root))
        lines
      end

      # The line that actually saves the turns: without it the banner is state an
      # agent re-reads out of the files the moment it writes anything.
      REFRESH = "Current as of session start. After you write, refresh with `okf pro state` — " \
                "do not re-read the files. `okf pro board` lists the lines; `okf pro capture`, " \
                "`promote`, `demote`, `journal open` and `close` write the mechanical shapes."

      # THE WHOLE BANNER, and there is only one of it.
      #
      # The bill is turns × context, not payload size. A measured session spent
      # nine tool calls and 40.9% of its tool output rediscovering state the gates
      # already compute — and state delivered here costs no turn at all, because
      # SessionStart runs whether anyone asks or not.
      #
      # Which is exactly why nothing may be said twice. This began as a structured
      # block appended UNDER three prose lines, and the two overlapped: in flight
      # and inbox were counted in both, and the snapshot was rendered in both. That
      # spends the saving the block exists to make, and leaves a reader working out
      # which of the two numbers is live.
      #
      # CHEAP SOURCES ONLY, and that is a constraint rather than a preference.
      # `State.call`'s default payload reads `board.md`, `log.md` and two directory
      # globs, and parses no concept. The two counters that would need
      # `Bundle::Reader.read` are never recomputed here — they arrive inside the
      # logged Snapshot line, printed whole and labelled by its day.
      #
      # Staleness is already covered elsewhere: the stop gate recomputes
      # independently and refuses a snapshot line that disagrees with the board.
      def state_block(payload, today)
        log = payload["log"]
        open_projects = payload["projects"]["open"]
        # The board's counters are formatted by `State`, not here: the banner's
        # whole promise is that it says what `okf pro state` would say, and two
        # renderings of the same eleven numbers drift into a reader having to
        # check which one they are looking at.
        lines = [ State.board_line(payload["board"], "Bundle state at session start —"),
                  "Log — newest day #{log["newest day"] || "none yet"} · journal for #{today} " \
                  "#{log["journal today"] ? "open" : "not opened"} · open projects #{open_projects.size}" \
                  "#{" (#{open_projects.join(", ")})" unless open_projects.empty?}",
                  snapshot_line(payload["last snapshot"]),
                  "Read the delta, not the status: a number that moved the wrong way is today's first signal." ]

        # Crack 2's other half: the collision made visible days before it lands.
        risk = payload["deadlines at risk"]
        unless risk.empty?
          lines << "Deadlines within 7d with nothing in flight against them:"
          risk.each { |line| lines << "  #{line}" }
        end
        lines
      end

      # The logged line WHOLE, with the day it was logged under and the label that
      # stops a reader taking it for today's. Both halves earn their place: the
      # twelve counters are what "read the delta" is read against, and two of them
      # — `unverified briefings` and `projects with 0 concepts` — can only be
      # recomputed by parsing the corpus, which this banner never does. A second
      # line restating those two said nothing this one does not.
      #
      # Latest by date, not last in the file: `State` reads the log newest-first,
      # because grepping the whole file for the last hit found its bottom — the
      # oldest entry — and from day two onward the banner reported the first-ever
      # counters, inverting the delta it exists to show.
      def snapshot_line(snap)
        return "Last snapshot: none yet" if snap.nil?

        "Last snapshot (#{snap["day"]}, not live): #{snap["line"]}"
      end

      # Addressed to the ADOPTER, not the maintainer, and that is the whole of
      # its tone: they are the ones paying for a missing verb, and they are the
      # only ones who can say which one it is. Nothing is ever filed
      # automatically — `--issue` prints a command a person decides to run.
      #
      # A recorder that could not write says so rather than printing a zero. A
      # zero and "unknown" are different states, and this is the one line in the
      # banner where confusing them would quietly retire the measurement.
      def friction_line(root)
        report = Friction.report(root)
        unless report.available
          return [ "Friction: the recorder could not write to .tmp/ at some point, so the count is " \
                   "unknown rather than zero. `okf pro friction --clear` starts it again." ]
        end

        # Only what a VERB covers, and that is the difference between a request and
        # a nag. Shell redirects are recorded too, and `covered_by` answers "Edit or
        # Write" for them — the trust guards read a tool event and a redirect
        # produces none — so counting them here claimed a verb could have done
        # something no verb covers. Worse: `shell-guard` records INTENT, at
        # PreToolUse, so the system working exactly as designed (guard fires, owner
        # denies, agent uses Edit) still incremented a lifetime counter that then
        # nagged every session until `--clear`. `okf pro friction` shows every row;
        # this line asks for a verb, so it counts only what a verb would answer.
        # A log that will not parse is a SHORT count, not a quiet one, and this
        # is the line where a zero and an unknown must never be confused. Only
        # the unwritable case was reported; an unreadable one said nothing at
        # all, which is the same lie one door along.
        lines = []
        if report.unreadable.positive?
          lines << "Friction: #{report.unreadable} recorded line(s) will not parse, so anything " \
                   "counted here is short by an unknown amount. `okf pro friction --clear` starts " \
                   "it again."
        end

        covered = report.events.count { |e| Friction.verb_covered?(e["via"], e["what"]) }
        return lines if covered.zero?

        # "so far", not "last session", and the difference is not pedantry: the
        # log is append-only and nothing prunes it, so this is a lifetime total.
        # A line that framed a cumulative number as this session's would nag
        # about a week nobody can change, and would keep nagging — which is the
        # standing-warning failure the whole design is built to avoid. Naming
        # the reset is what makes the number actionable.
        lines << "#{covered} bundle edit(s) so far were done by hand that an `okf pro` verb " \
                 "could do. If one of them should be a verb, please tell the maintainer — `okf pro " \
                 "friction --issue` prints a ready-to-paste report, and `--clear` resets the count. " \
                 "It helps more than you think."
        lines
      end
    end
  end
end
