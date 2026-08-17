# frozen_string_literal: true

require "test_helper"

# Rule 3 as the hook reaches it — through a Target rather than a string. The
# counting rules themselves are pinned in test/unit/budget_test.rb; what is
# under test here is which edits the gate has an opinion about at all.
class BudgetThroughTargetTest < OKF::Pro::TestCase
  def test_ignores_edits_to_anything_but_the_board
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      target = OKF::Pro::Target.for(edit_event(b.path, "glossary/term.md"))

      assert_empty OKF::Pro::Budget.cap_check(target)
    end
  end

  def test_refuses_a_breach_through_the_target
    with_bundle do |b|
      b.in_flight("one", "two", "three").budget(declared: 3, cap: 2)
      target = OKF::Pro::Target.for(edit_event(b.path, "board.md"))

      assert_match(/RULE 3/, OKF::Pro::Budget.cap_check(target).first)
    end
  end

  def test_a_nil_target_is_not_a_pass_it_is_no_opinion
    assert_empty OKF::Pro::Budget.cap_check(nil)
  end
end

# Rule 3's own question. Never a verdict, and quiet in exactly two cases: a
# journal too young to answer, and a demand the journal linked recently.
class DormancyTest < OKF::Pro::TestCase
  TODAY = Date.new(2026, 8, 12) # a Wednesday; five working days back is 08-06

  def in_flight_project(b)
    b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
    b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")
  end

  def journal(b, day, text)
    b.write("journal/#{day}.md", "---\ntype: Journal Entry\ntitle: #{day}\ndescription: Fixture day.\n---\n\n#{text}\n")
  end

  def test_a_recently_journaled_demand_raises_no_question
    with_bundle do |b|
      in_flight_project(b)
      journal(b, "2026-08-01", "Started things.")
      journal(b, "2026-08-10", "Chased [/projects/home-move/](/projects/home-move/index.md) again.")

      assert_empty OKF::Pro::Budget.dormancy_questions(b.bundle_path, today: TODAY)
    end
  end

  def test_an_unjournaled_demand_gets_the_question
    with_bundle do |b|
      in_flight_project(b)
      journal(b, "2026-08-01", "Started things, linked /projects/home-move once, long ago.")
      journal(b, "2026-08-10", "A day about something else entirely.")

      questions = OKF::Pro::Budget.dormancy_questions(b.bundle_path, today: TODAY)

      assert_equal 1, questions.size
      assert_match(%r{/projects/home-move/}, questions.first)
      assert_match(/still in flight, or backlog pretending\?/, questions.first)
    end
  end

  # A bundle in its first week cannot be dormant, only new.
  def test_a_journal_younger_than_the_window_stays_quiet
    with_bundle do |b|
      in_flight_project(b)
      journal(b, "2026-08-11", "Yesterday, and that is all the history there is.")

      assert_empty OKF::Pro::Budget.dormancy_questions(b.bundle_path, today: TODAY)
    end
  end

  def test_no_journal_at_all_stays_quiet
    with_bundle do |b|
      in_flight_project(b)

      assert_empty OKF::Pro::Budget.dormancy_questions(b.bundle_path, today: TODAY)
    end
  end

  # Law 2: a demand with no project link is one dormancy cannot see, and the
  # check says so instead of skipping it in silence.
  def test_a_linkless_demand_is_confessed_not_skipped
    with_bundle do |b|
      b.in_flight("call the movers back about the quote")
      journal(b, "2026-08-01", "Old enough to answer.")

      questions = OKF::Pro::Budget.dormancy_questions(b.bundle_path, today: TODAY)

      assert_equal 1, questions.size
      assert_match(/carry no \/projects\/ link — dormancy cannot see them/, questions.first)
    end
  end

  # The write-time door and the grammar pass, joined: a board over cap only
  # when the hidden line is counted returned [] here while grammar() flagged
  # the line at audit and Stop — the one moment the writer was still holding
  # the pen was the one moment nothing spoke.
  def test_cap_check_flags_a_line_the_counters_cannot_see
    with_bundle do |b|
      b.in_flight("one")
      dir = b.path
      board_path = File.join(dir, "board.md")
      board = OKF::Pro.read_text(board_path)
      File.write(board_path, board.sub("## In flight\n", "## In flight\n  - a demand hidden from the cap\n"))

      findings = OKF::Pro::Budget.cap_check(OKF::Pro::Target.for(edit_event(dir, "board.md")))

      assert(findings.any? { |m| m =~ /no counter can see it.*hidden from the cap/ }, findings.inspect)
    end
  end

  def test_cap_check_stays_quiet_on_a_grammar_clean_board
    with_bundle do |b|
      b.in_flight("one").inbox("2026-08-12 — heard at lunch")

      assert_empty OKF::Pro::Budget.cap_check(OKF::Pro::Target.for(edit_event(b.path, "board.md")))
    end
  end
end
