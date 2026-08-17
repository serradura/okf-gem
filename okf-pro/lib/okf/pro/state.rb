# frozen_string_literal: true

module OKF
  module Pro
    # What is on the board, in one call.
    #
    # THE MEASUREMENT THIS EXISTS FOR. A session adding one task to a seeded
    # bundle spent 40.9% of its tool output rediscovering state — the board, the
    # log, the project and journal indexes, read raw, one `cat` per question —
    # and called no `okf pro` verb at all. Nine calls answered what the gates
    # already compute on every Stop. So there is no new logic here: every
    # aggregation below already existed and was consumed only by a refusal.
    #
    # CHEAP BY DEFAULT, and that is a contract rather than an optimisation. The
    # default payload reads `board.md`, `log.md` and two directory globs, and
    # parses no concept — the same sources the session banner uses, so a reader
    # can trust the two to agree. `--full` is where `Bundle::Reader.read` lives:
    # the attestation report, the pairing invariants, and the live unverified
    # count, behind ONE parse shared by all three.
    #
    # A contract that names its sources is a contract to check before adding
    # one. The friction log was added here and did not belong: it is telemetry
    # about the tooling rather than state of the bundle, it is append-only with
    # nothing pruning it, and `render` never printed the field — so the cheap
    # default paid for an unbounded read only `--json` could see.
    # `okf pro friction` is the verb that answers it.
    #
    # Shell, not core: it reads the disk. The arithmetic it reports is Board's,
    # Log's, Snapshot's and Pairing's, all of it pure and all of it already
    # tested against text rather than against a fixture.
    module State
      module_function

      def call(root, today: Date.today, full: false)
        board = Pro.read_text(File.join(root, "board.md"))
        log_path = File.join(root, "log.md")
        log = File.exist?(log_path) ? Pro.read_text(log_path) : ""
        vis = Board.visible(board)

        payload = {
          "root" => root,
          "as of" => today.to_s,
          "board" => board_state(vis, today),
          "deadlines at risk" => Snapshot.looming_deadlines(vis, today).map(&:strip),
          "log" => log_state(root, log, today),
          "projects" => { "open" => Pairing.open_projects(root).sort },
          "last snapshot" => last_snapshot(log)
        }
        payload["full"] = full_state(root, board) if full
        payload
      end

      def board_state(vis, today)
        budget = Board.budget(vis)
        inbox = Board.visible_section_lines(vis, "Inbox")
        waiting = Board.visible_section_lines(vis, "Waiting")
        ages = inbox.map { |l| Board.line_date(l) }.compact.map { |d| (today - d).to_i }
        {
          "in flight" => Board.visible_section_lines(vis, "In flight").size,
          "cap" => budget&.cap,
          "declared" => budget&.declared,
          "backlog" => Board.visible_section_lines(vis, "Backlog").size,
          "waiting" => waiting.size,
          "past chase" => waiting.map { |l| Board.chase_date(l) }.compact.count { |d| d < today },
          "inbox" => inbox.size,
          "oldest" => ages.max || 0,
          "to read" => Board.visible_section_lines(vis, "To read").size,
          "deadlines" => Board.visible_section_lines(vis, "Deadlines").size,
          "conflicts open" => Snapshot.conflicts(vis)
        }
      end

      def log_state(root, log, today)
        {
          "newest day" => Log.newest_day(log),
          "journal today" => File.file?(File.join(root, "journal", "#{today}.md"))
        }
      end

      # Labelled by the day it was logged under, never as live. The counters
      # here are free — the banner already prints the line, and parsing it costs
      # a regex — but two of them (`unverified briefings`, `projects with 0
      # concepts`) can only be recomputed by parsing the bundle, so a reader
      # who is told them without the date would read a stale number as current.
      def last_snapshot(log)
        day, line = Log.latest_snapshot_entry(log)
        return nil if line.nil?

        { "day" => day, "line" => line.strip, "counters" => Snapshot.parse(line) }
      end

      # The one parse, shared by all three. Ordered so the reader meets the
      # invariants before the listing: a pairing failure is a thing to fix, and
      # an unverified concept is the truth about what is owed.
      def full_state(root, board)
        concepts = ::OKF::Bundle::Reader.read(root).concepts
        {
          "pairing" => Pairing.failures(root, board: board, concepts: concepts).map { |m| m.sub(/\A— /, "") },
          "unverified" => Attestation.report(root, concepts: concepts).map(&:strip),
          "unverified briefings" => Pairing.unverified_ids(concepts).size
        }
      end

      # ── human rendering ──────────────────────────────────────────────────
      #
      # The default, because the consumer is also a person doing QA — and
      # because a human line an agent reads costs the same tokens as JSON it
      # has to re-serialise into prose anyway.
      # The board's counters as one line, and the ONE place they are formatted.
      # `okf pro state` and the session banner both print it, and the banner's
      # whole promise is that it says what the verb would say — two renderings
      # of the same eleven numbers would drift into a reader having to check
      # which one they were looking at.
      def board_line(board, label)
        "#{label} in flight #{board["in flight"]}/#{board["cap"] || "?"} · backlog #{board["backlog"]} · " \
          "waiting #{board["waiting"]} (#{board["past chase"]} past chase) · inbox #{board["inbox"]} " \
          "(oldest #{board["oldest"]}d) · to read #{board["to read"]} · deadlines #{board["deadlines"]} · " \
          "conflicts open #{board["conflicts open"]}"
      end

      def render(payload)
        b = payload["board"]
        lines = [ board_line(b, "Board —") ]
        if b["declared"] && b["declared"] != b["in flight"]
          lines << "  header declares #{b["declared"]} in flight and the section holds " \
                   "#{b["in flight"]} — fix the header."
        end

        risk = payload["deadlines at risk"]
        unless risk.empty?
          lines << "Deadlines within 7d with nothing in flight against them:"
          risk.each { |line| lines << "  #{line}" }
        end

        log = payload["log"]
        lines << "Log — newest day #{log["newest day"] || "none yet"} · journal for " \
                 "#{payload["as of"]} #{log["journal today"] ? "open" : "not opened"}"

        open_projects = payload["projects"]["open"]
        lines << "Open projects (#{open_projects.size})#{": #{open_projects.join(", ")}" unless open_projects.empty?}"

        lines.concat(render_snapshot(payload["last snapshot"]))
        lines.concat(render_full(payload["full"])) if payload["full"]
        lines
      end

      def render_snapshot(snap)
        return [ "Last snapshot: none yet" ] if snap.nil?

        counters = snap["counters"]
        [ "As of #{snap["day"]}, the last logged snapshot — unverified briefings " \
          "#{counters["unverified briefings"] || "?"} · projects with 0 concepts " \
          "#{counters["projects with 0 concepts"] || "?"} (`--full` recomputes these live)" ]
      end

      def render_full(full)
        lines = [ "Live from the corpus — unverified briefings #{full["unverified briefings"]}" ]
        if full["pairing"].empty?
          lines << "Pairing — the board and the work are in step."
        else
          lines << "Pairing — #{full["pairing"].size} finding(s):"
          full["pairing"].each { |m| lines << "  #{m}" }
        end
        if full["unverified"].empty?
          lines << "Awaiting the owner's read — nothing."
        else
          lines << "Awaiting the owner's read (#{full["unverified"].size}):"
          full["unverified"].each { |m| lines << "  #{m}" }
        end
        lines
      end
    end
  end
end
