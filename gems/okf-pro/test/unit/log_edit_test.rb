# frozen_string_literal: true

require "test_helper"

# The log's one text transform, and the convention it exists to keep: newest
# day first. Every earlier defect in `log.rb` turned on that convention being
# prose rather than code — the audit interrogating the oldest day, the banner
# printing day one's counters forever — so a writer that appended a new day at
# the bottom would recreate all of them at once.
class LogEditTest < OKF::Pro::TestCase
  Edit = OKF::Pro::Log::Edit

  DATED = <<~LOG
    # Update Log

    Prose about the log.

    ## 2026-08-16

    * Something happened.

    ## 2026-08-10

    * Something older.
  LOG

  UNDATED = "# Update Log\n\nNothing logged yet.\n"

  test "a new day goes above every existing day, not at the end of the file" do
    text, = Edit.add_entry(DATED, "2026-08-17", "* Closed a project.")

    assert_operator text.index("## 2026-08-17"), :<, text.index("## 2026-08-16")
    assert_match(/## 2026-08-17\n\n\* Closed a project\.\n\n## 2026-08-16/, text)
  end

  test "an entry for a day already present joins that day's last line" do
    text, = Edit.add_entry(DATED, "2026-08-16", "* And another thing.")

    assert_match(/\* Something happened\.\n\* And another thing\.\n\n## 2026-08-10/, text)
    refute_includes text, "## 2026-08-16\n\n## 2026-08-16"
  end

  test "the first ever day lands at the end of an undated log" do
    text, = Edit.add_entry(UNDATED, "2026-08-17", "* The first thing.")

    assert_match(/Nothing logged yet\.\n\n## 2026-08-17\n\n\* The first thing\.\n\z/, text)
  end

  # The delta is the caller's claim to `Conserve`, and a blank line is a line.
  # A guard that let an unstated blank through is a guard an edit can be walked
  # past one blank at a time.
  test "every line spliced in is declared, blank lines included" do
    [ [ DATED, "2026-08-17" ], [ DATED, "2026-08-16" ], [ UNDATED, "2026-08-17" ] ].each do |before, day|
      text, added = Edit.add_entry(before, day, "* An entry.")

      assert_empty OKF::Pro::Conserve.check(before, text, added: added),
        "the transform's own claim does not survive the guard for #{day}"
    end
  end

  test "a log with no final newline does not get its last line concatenated" do
    text, added = Edit.add_entry("# Update Log", "2026-08-17", "* An entry.")

    assert_equal "# Update Log\n", text.lines.first
    assert_empty OKF::Pro::Conserve.check("# Update Log", text, added: added)
  end

  # The whole reason `latest_snapshot_entry` exists beside the day walk: the
  # written day must be the one the readers then find.
  test "the day a new entry creates is the day the readers see as newest" do
    text, = Edit.add_entry(DATED, "2026-08-17", "* An entry.")

    assert_equal "2026-08-17", OKF::Pro::Log.newest_day(text)
  end
end
