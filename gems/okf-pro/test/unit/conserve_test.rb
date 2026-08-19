# frozen_string_literal: true

require "test_helper"

# The write contract, as a property rather than a promise.
#
# Failure mode 07 is an LLM regenerating a view and dropping a line, silently.
# Every write verb states the delta it intends and hands it here; if the actual
# delta differs, nothing is written. So the tests that matter are the ones where
# a transform did something plausible and slightly wrong — those are the shapes
# that reach production, not the ones where it emptied the file.
class ConserveTest < OKF::Pro::TestCase
  BOARD = "## Inbox\n- a\n- b\n\n## Backlog\n- c\n"

  test "an append that matches its claim is conserved" do
    after = "## Inbox\n- a\n- b\n- d\n\n## Backlog\n- c\n"

    assert_empty OKF::Pro::Conserve.check(BOARD, after, added: [ "- d" ])
  end

  test "an unchanged file with an unchanged claim is conserved" do
    assert_empty OKF::Pro::Conserve.check(BOARD, BOARD)
  end

  # The whole point. The append landed and a line went with it — no error, no
  # exception, a file that still looks like a board.
  test "a line dropped alongside an intended append is a finding" do
    after = "## Inbox\n- a\n- d\n\n## Backlog\n- c\n"

    findings = OKF::Pro::Conserve.check(BOARD, after, added: [ "- d" ])

    assert_equal 1, findings.size
    assert_match(/removed that the edit did not intend: - b/, findings.first)
  end

  test "a line added that nobody claimed is a finding" do
    after = "## Inbox\n- a\n- b\n- d\n- sneaked\n\n## Backlog\n- c\n"

    findings = OKF::Pro::Conserve.check(BOARD, after, added: [ "- d" ])

    assert_equal 1, findings.size
    assert_match(/added that the edit did not intend: - sneaked/, findings.first)
  end

  # The other direction, and it is a refusal too: an edit that did less than it
  # said is how a promotion silently no-ops and reports success.
  test "a claimed addition that never happened is a finding" do
    findings = OKF::Pro::Conserve.check(BOARD, BOARD, added: [ "- d" ])

    assert_equal 1, findings.size
    assert_match(/meant to have added are not: - d/, findings.first)
  end

  test "a claimed removal that never happened is a finding" do
    findings = OKF::Pro::Conserve.check(BOARD, BOARD, removed: [ "- b" ])

    assert_match(/meant to have removed are not: - b/, findings.first)
  end

  # A move is invisible to a multiset by construction, so it is asserted
  # directly — otherwise "move it", "delete it and add it back" and "do
  # nothing" are the same claim.
  test "a move across sections is conserved" do
    after = "## Inbox\n- a\n\n## Backlog\n- c\n- b\n"

    assert_empty OKF::Pro::Conserve.check(BOARD, after, moved: [ "- b" ])
  end

  test "a move whose line vanished is a finding in both directions" do
    after = "## Inbox\n- a\n\n## Backlog\n- c\n"

    findings = OKF::Pro::Conserve.check(BOARD, after, moved: [ "- b" ])

    assert_match(/removed that the edit did not intend: - b/, findings.join("\n"))
    assert_match(/the line to move is gone from the result: - b/, findings.join("\n"))
  end

  test "a move of a line that was never there is a finding" do
    findings = OKF::Pro::Conserve.check(BOARD, BOARD, moved: [ "- nope" ])

    assert_match(/the line to move is not in the file as it stands: - nope/, findings.join("\n"))
  end

  # Counted, not set-membership. A board carrying the same commitment twice is
  # carrying it twice, and an edit that quietly deduplicates has dropped one.
  test "duplicate lines are counted rather than folded together" do
    before = "- a\n- a\n"

    findings = OKF::Pro::Conserve.check(before, "- a\n", removed: [])

    assert_match(/1 line\(s\) removed that the edit did not intend: - a/, findings.first)
  end

  # Whitespace inside a line is content on a board — the leading `- ` is the
  # counters' own grammar — so an edit that reindents is an edit that changed
  # something, and this must see it.
  test "reindentation is not conservation" do
    findings = OKF::Pro::Conserve.check("- a\n", "  - a\n")

    refute_empty findings
  end

  # The one normalisation, and it has to hold or every writer would have to
  # remember to terminate the file itself.
  test "a missing final newline is not a delta" do
    assert_empty OKF::Pro::Conserve.check("- a", "- a\n")
  end
end
