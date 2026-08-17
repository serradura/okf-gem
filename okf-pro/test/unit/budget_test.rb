# frozen_string_literal: true

require "test_helper"

# Rule 3. Two refusals, and the second matters as much as the first: a header
# that lies about its own section is worse than a missing one, because the
# board's whole job is to be trustworthy at a glance.
class BudgetTest < OKF::Pro::TestCase
  def board(declared:, cap:, count:)
    lines = Array.new(count) { |i| "- item #{i + 1}" }.join("\n")
    "# Board\n\n**In flight: #{declared}/#{cap}** · updated today\n\n## In flight\n#{lines}\n\n## Backlog\n"
  end

  def test_passes_when_the_board_is_honest_and_under_cap
    assert_empty OKF::Pro::Budget.check_text(board(declared: 3, cap: 5, count: 3))
  end

  def test_passes_at_exactly_the_cap
    assert_empty OKF::Pro::Budget.check_text(board(declared: 5, cap: 5, count: 5))
  end

  def test_refuses_over_the_cap
    refusal = OKF::Pro::Budget.check_text(board(declared: 6, cap: 5, count: 6))

    assert_equal 1, refusal.size
    assert_match(/RULE 3/, refusal.first)
    assert_match(/6 in flight against a cap of 5/, refusal.first)
    assert_match(/renegotiation/, refusal.first)
  end

  # Renegotiating the cap is allowed — that is the rule's whole point. Raising
  # the number in the header is the visible act that makes it allowed.
  def test_a_raised_cap_is_accepted
    assert_empty OKF::Pro::Budget.check_text(board(declared: 6, cap: 6, count: 6))
  end

  def test_refuses_a_header_that_disagrees_with_its_section
    refusal = OKF::Pro::Budget.check_text(board(declared: 1, cap: 5, count: 3))

    assert_equal 1, refusal.size
    assert_match(/Header claims 1 in flight; the section holds 3/, refusal.first)
  end

  def test_refuses_a_board_that_lost_its_header
    refusal = OKF::Pro::Budget.check_text("# Board\n\n## In flight\n- one\n")

    assert_equal 1, refusal.size
    assert_match(/lost its 'In flight: k\/CAP' header/, refusal.first)
  end

  # Over the cap wins when both are wrong: overload is the finding, and a
  # correction to the header alone would leave it standing.
  def test_the_cap_breach_outranks_the_mismatch
    refusal = OKF::Pro::Budget.check_text(board(declared: 2, cap: 5, count: 7))

    assert_match(/RULE 3/, refusal.first)
  end
end
