# frozen_string_literal: true

module OKF
  module Pro
    # Rule 2's counters, derived. This is derivation returned as a *checker*:
    # it computes the mechanical line and verifies the one a person appended —
    # it never writes one. Agent Drift killed the generator (a regenerated view
    # drops a task silently); a checker that disagrees out loud has no way to
    # drop anything silently, which is why it gets to exist first.
    module Snapshot
      # The line's vocabulary, in the order the line reads. Parse patterns are
      # anchored on the field names so a hand-typed line with extra spacing
      # still parses, and a line missing a field says so as nil rather than
      # borrowing a neighbour's number. "in flight" requires the slash so the
      # phrase inside "deadlines within 7d not in flight" cannot satisfy it.
      #
      # `oldest` takes an optional sign, and it is the only field that can:
      # every other counter is a count, and `oldest` is a SUBTRACTION. A
      # capture dated in the future — one mistyped year — gives a negative age,
      # `render` wrote `oldest -365d`, and a pattern demanding a digit straight
      # after `oldest ` read that as nothing at all. `verify` then disagreed
      # with the line `render` had just produced, so the stop gate refused and
      # offered as the fix the very line it was refusing. Pasting it refused
      # again: a deadlock with no self-service exit.
      #
      # The age is NOT clamped to zero, deliberately. Clamping would make the
      # gate self-consistent by making the counter lie, and `oldest 0d` on a
      # line nobody can explain is the quiet-wrong-number failure this whole
      # module exists to refuse. A negative age is the honest reading of a
      # future-dated capture, and it is visible in the log where a person will
      # ask about it.
      PATTERNS = {
        "inbox" => /inbox (\d+)/,
        "oldest" => /oldest (-?\d+)d/,
        "in flight" => %r{in flight (\d+)/\d+},
        "cap" => %r{in flight \d+/(\d+)},
        "waiting" => /waiting (\d+)/,
        "past chase" => /\((\d+) past chase\)/,
        "backlog" => /backlog (\d+)/,
        "to read" => /to read (\d+)/,
        "unverified briefings" => /unverified briefings (\d+)/,
        "conflicts open" => /conflicts open (\d+)/,
        "deadlines within 7d not in flight" => /deadlines within 7d not in flight (\d+)/,
        "projects with 0 concepts" => /projects with 0 concepts (\d+)/
      }.freeze

      module_function

      # `board:` and `concepts:` are the same courtesy Pairing.failures
      # extends: a caller that already paid for the read hands it over. The
      # stop gate reads the board and parses the bundle once for all of its
      # checks; without the seam it paid twice per Stop.
      def counters(root, today: Date.today, board: nil, concepts: nil)
        board ||= Pro.read_text(File.join(root, "board.md"))
        concepts ||= ::OKF::Bundle::Reader.read(root).concepts
        # One strip for all twelve counters — every Board.count call was
        # re-running the whole comment strip, ~10 times per Stop.
        vis = Board.visible(board)
        budget = Board.budget(vis)
        inbox = Board.visible_section_lines(vis, "Inbox")
        waiting = Board.visible_section_lines(vis, "Waiting")
        ages = inbox.map { |l| Board.line_date(l) }.compact
                    .map { |d| (today - d).to_i }
        chases = waiting.map { |l| Board.chase_date(l) }.compact

        {
          "inbox" => inbox.size,
          "oldest" => ages.max || 0,
          "in flight" => Board.visible_section_lines(vis, "In flight").size,
          "cap" => budget ? budget.cap : 0,
          "waiting" => waiting.size,
          "past chase" => chases.count { |d| d < today },
          "backlog" => Board.visible_section_lines(vis, "Backlog").size,
          "to read" => Board.visible_section_lines(vis, "To read").size,
          "unverified briefings" => Pairing.unverified_ids(concepts).size,
          "conflicts open" => conflicts(vis),
          "deadlines within 7d not in flight" => looming_deadlines(vis, today).size,
          "projects with 0 concepts" => empty_projects(root).size
        }
      end

      def line(root, today: Date.today, board: nil, concepts: nil)
        render(counters(root, today: today, board: board, concepts: concepts))
      end

      def render(c)
        "* **Snapshot**: inbox #{c["inbox"]} (oldest #{c["oldest"]}d) " \
          "· in flight #{c["in flight"]}/#{c["cap"]} " \
          "· waiting #{c["waiting"]} (#{c["past chase"]} past chase) " \
          "· backlog #{c["backlog"]} · to read #{c["to read"]} " \
          "· unverified briefings #{c["unverified briefings"]} " \
          "· conflicts open #{c["conflicts open"]} " \
          "· deadlines within 7d not in flight #{c["deadlines within 7d not in flight"]} " \
          "· projects with 0 concepts #{c["projects with 0 concepts"]}"
      end

      def parse(line)
        PATTERNS.transform_values do |pattern|
          match = line.to_s.match(pattern)
          match && match[1].to_i
        end
      end

      # The appended line against the bundle it summarises. Field by field, so
      # the refusal names what drifted instead of waving at the whole line —
      # and the recomputed line is in the message, because the fix is a paste.
      def verify(root, line, today: Date.today, board: nil, concepts: nil)
        want = counters(root, today: today, board: board, concepts: concepts)
        got = parse(line)
        wrong = want.reject { |key, value| got[key] == value }
        return [] if wrong.empty?

        detail = wrong.map { |key, value| "#{key} is #{value}, the line says #{got[key] || "nothing"}" }
        [ "— the Snapshot line disagrees with the bundle it summarises: #{detail.join("; ")}.\n  " \
          "The mechanical line, recomputed:\n  #{render(want)}" ]
      end

      # Conflict lines are dated captures wherever they sit — Inbox by rule,
      # but a line that migrated to Backlog is still an open conflict.
      def conflicts(board)
        # visible() is a fixpoint, so a caller handing over already-visible
        # text (counters does) costs one no-op scan, not a second strip.
        Board.visible(board).each_line.count { |l| l.start_with?("- ") && l.include?("Resolve:") }
      end

      # Crack 2's confession: deadlines due within the window — or already due
      # — that share no project link with any in-flight line. A deadline line
      # with no link cannot be paired, so it counts: the board cannot show
      # anyone is on it, and "probably someone is" is not a counter.
      def looming_deadlines(board, today, window: 7)
        vis = Board.visible(board)
        covered = Board.visible_section_lines(vis, "In flight").flat_map { |l| project_slugs(l) }
        Board.visible_section_lines(vis, "Deadlines").select do |line|
          date = Board.line_date(line)
          next false unless date && date <= today + window

          (project_slugs(line) & covered).empty?
        end
      end

      def project_slugs(line)
        Board.targets(line).map { |t| t[%r{\A/projects/([^/\s]+)}i, 1]&.downcase }.compact
      end

      # An open project holding nothing but its own index: work happening with
      # no knowledge landing — the blind spot the structure itself created.
      def empty_projects(root)
        Pairing.open_projects(root).select do |name|
          Dir.glob(File.join(root, "projects", name, "**", "*.md"))
             .reject { |f| File.basename(f) == "index.md" }
             .empty?
        end
      end
    end
  end
end
