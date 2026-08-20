# frozen_string_literal: true

module OKF
  module Pro
    # Rule 3 — in flight is a budget.
    #
    # Two refusals, and the second matters as much as the first. Over the cap is
    # overload. A header that disagrees with the section under it is worse than
    # no header: the board's whole job is to be the one page you can trust at a
    # glance, and a budget face that lies costs more than an absent one.
    module Budget
      # Five working days without a journal link is the dormancy window — the
      # budget's own question, not a verdict.
      #
      # It is NOT tunable, and the comment here used to say it was ("tuned in the
      # skill's Rule 3"), which was false in the direction that costs the most:
      # the skill states the number in prose, an adopter who changed it there
      # would see nothing happen, and the gate would keep asking on the old
      # window while the written rule said otherwise. Nobody has asked for a
      # knob; what the situation needed was for the two statements to be one
      # fact. `test/unit/dormancy_window_test.rb` pins the skill's number to this
      # constant, so changing it here fails until the skill follows.
      DORMANCY_DAYS = 5

      module_function

      def cap_check(target)
        return [] if target.nil?
        return [] unless target.rel == "board.md"
        return [] unless target.exist?("board.md")

        board = target.read("board.md")
        # Grammar rides along at the write-time door on purpose: the stray
        # bullet and the unreadable date are exactly the lines the counters
        # below cannot see, and a cap check that stays quiet while its own
        # input is partly invisible has already lost the argument. Audit
        # and stop gate run the same pass; this door ran only the counters,
        # so the one moment the writer was still holding the pen was the
        # one moment nothing spoke.
        check_text(board) + Board.grammar(board)
      end

      def check_text(board)
        board = Board.visible(board)
        budget = Board.budget(board)
        unless budget
          return [ "board.md lost its 'In flight: k/CAP' header — Rule 3's visible budget. Restore it first." ]
        end

        count = Board.count(board, "In flight")

        if count > budget.cap
          return [ "RULE 3 — #{count} in flight against a cap of #{budget.cap}. Promotion requires demotion, " \
                   "or a visible renegotiation (new cap in the header; renegotiations are journal-worthy)." ]
        end

        if budget.declared != count
          return [ "Header claims #{budget.declared} in flight; the section holds #{count}. " \
                   "Fix the header — a wrong budget face is worse than none." ]
        end

        []
      end

      # The dormancy questions: in-flight demands no journal entry has linked
      # in DORMANCY_DAYS working days. Questions, never verdicts — "still in
      # flight, or backlog pretending? Either answer is fine; holding a slot
      # without moving is not."
      #
      # Two silences are deliberate. A journal younger than the window stays
      # quiet — a bundle in its first week cannot be dormant, only new. And a
      # demand whose promotion was journaled (promotions are journal-worthy)
      # is linked from day one, so the fresh-promotion false positive is
      # already covered by the discipline this question serves.
      def dormancy_questions(root, today: Date.today, board: nil)
        board_path = File.join(root, "board.md")
        return [] if board.nil? && !File.exist?(board_path)

        entries = journal_entries(root)
        return [] if entries.empty?

        start = window_start(today)
        return [] if entries.map(&:first).min > start

        # Contained: the root is in hand, and a journal entry symlinked in from
        # outside the bundle is not this bundle's record of a day. One that
        # escapes is dropped rather than raising — dormancy is a question, not a
        # gate, and an unreadable entry means "no evidence of work", which is
        # the answer that keeps the question being asked.
        recent = entries.select { |day, _| day >= start }
                        .map { |_, path| safely(root, path) }
                        .join("\n").downcase

        lines = Board.section_lines(board || safely(root, board_path), "In flight")
        questions = lines.map do |line|
          slugs = Snapshot.project_slugs(line)
          next if slugs.empty?
          next if slugs.any? { |slug| recent.include?("/projects/#{slug}") }

          "Rule 3, dormancy — no journal entry has linked /projects/#{slugs.first}/ in " \
            "#{DORMANCY_DAYS} working days: still in flight, or backlog pretending?"
        end.compact

        # Law 2: the check confesses its own blind spot rather than skipping it
        # in silence — a demand with no project link is one dormancy cannot see.
        unlinked = lines.count { |line| Snapshot.project_slugs(line).empty? }
        questions << "Note: #{unlinked} in-flight line(s) carry no /projects/ link — dormancy cannot see them." if unlinked.positive?

        questions
      end

      def safely(root, path)
        Pro.read_contained(root, path)
      rescue ::OKF::Path::Error, ::Errno::ENOENT
        ""
      end

      def journal_entries(root)
        Dir.glob(File.join(root, "journal", "*.md")).map do |path|
          match = File.basename(path).match(/\A(\d{4}-\d{2}-\d{2})\.md\z/)
          next unless match

          day = Board.parse_date(match[1])
          [ day, path ] if day
        end.compact
      end

      # Walk back from today until the window holds DORMANCY_DAYS working days.
      # Weekends extend the window rather than counting against it — legitimate
      # stillness is what keeps the dormancy alarm honest.
      def window_start(today, days = DORMANCY_DAYS)
        date = today
        counted = 0
        loop do
          counted += 1 if (1..5).cover?(date.wday)
          break if counted >= days

          date -= 1
        end
        date
      end
    end
  end
end
