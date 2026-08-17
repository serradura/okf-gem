# frozen_string_literal: true

require "test_helper"

# The line as text — render and parse, no disk. What is being pinned is the
# vocabulary: a line the renderer writes must come back through the parser
# unchanged, and a line missing a field must say so as nil rather than
# borrowing a neighbour's number.
class SnapshotLineTest < OKF::Pro::TestCase
  COUNTERS = {
    "inbox" => 3, "oldest" => 11, "in flight" => 4, "cap" => 5,
    "waiting" => 2, "past chase" => 1, "backlog" => 6, "to read" => 2,
    "unverified briefings" => 1, "conflicts open" => 2,
    "deadlines within 7d not in flight" => 1, "projects with 0 concepts" => 0
  }.freeze

  def test_render_and_parse_roundtrip
    assert_equal COUNTERS, OKF::Pro::Snapshot.parse(OKF::Pro::Snapshot.render(COUNTERS))
  end

  def test_renders_the_canonical_shape
    line = OKF::Pro::Snapshot.render(COUNTERS)

    assert line.start_with?("* **Snapshot**: inbox 3 (oldest 11d) · in flight 4/5")
    assert_match(/deadlines within 7d not in flight 1 · projects with 0 concepts 0\z/, line)
  end

  # "not in flight 0" contains the words "in flight 0"; the budget field must
  # not be satisfied by the deadline field's tail.
  def test_the_in_flight_field_requires_the_slash
    parsed = OKF::Pro::Snapshot.parse(
      "* **Snapshot**: in flight 4/5 · deadlines within 7d not in flight 0"
    )

    assert_equal 4, parsed["in flight"]
    assert_equal 5, parsed["cap"]
    assert_equal 0, parsed["deadlines within 7d not in flight"]
  end

  def test_a_line_missing_a_field_parses_it_as_nil
    parsed = OKF::Pro::Snapshot.parse("* **Snapshot**: inbox 1 (oldest 0d) · in flight 1/5")

    assert_equal 1, parsed["inbox"]
    assert_nil parsed["deadlines within 7d not in flight"]
    assert_nil parsed["projects with 0 concepts"]
  end

  def test_garbage_parses_to_all_nil
    assert OKF::Pro::Snapshot.parse("not a snapshot at all").values.all?(&:nil?)
  end

  def test_a_commented_resolve_line_is_not_an_open_conflict
    board = "## Inbox\n- 2026-08-12 — Resolve: [/a.md] says X, [/b.md] says Y\n<!-- - 2026-08-12 — Resolve: a sample in the docs -->\n"

    assert_equal 1, OKF::Pro::Snapshot.conflicts(board)
  end
end
