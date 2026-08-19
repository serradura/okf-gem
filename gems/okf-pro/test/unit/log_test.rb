# frozen_string_literal: true

require "test_helper"

class LogTest < OKF::Pro::TestCase
  LOG = <<~MD
    # Update Log

    ## 2026-08-12
    * **Creation**: something.
    * **Snapshot**: inbox 1 · in flight 1/5

    ## 2026-08-11
    * **Update**: something else.
    * **Snapshot**: inbox 0 · in flight 1/5
  MD

  def test_finds_the_snapshot_under_that_day
    assert OKF::Pro::Log.snapshot_under?(LOG, "2026-08-12")
    assert OKF::Pro::Log.snapshot_under?(LOG, "2026-08-11")
  end

  # The regression. The shell version set its flag at the day heading and
  # never cleared it, so yesterday's snapshot satisfied today — which is
  # exactly the question being asked.
  def test_a_previous_days_snapshot_does_not_satisfy_today
    log = <<~MD
      # Update Log

      ## 2026-08-12
      * **Creation**: something.

      ## 2026-08-11
      * **Snapshot**: inbox 0 · in flight 1/5
    MD

    refute OKF::Pro::Log.snapshot_under?(log, "2026-08-12")
    assert OKF::Pro::Log.snapshot_under?(log, "2026-08-11")
  end

  def test_a_day_with_no_heading_has_no_snapshot
    refute OKF::Pro::Log.snapshot_under?(LOG, "2026-08-10")
  end

  def test_handles_an_empty_log
    refute OKF::Pro::Log.snapshot_under?("", "2026-08-12")
    assert_nil OKF::Pro::Log.newest_day("")
  end

  def test_newest_day_is_the_maximum_date
    assert_equal "2026-08-12", OKF::Pro::Log.newest_day(LOG)
  end

  # The regression: nothing enforces the file's newest-first convention, and
  # taking the first heading made the audit interrogate the oldest day — which
  # had its snapshot — while the real newest day had none. CI passed on it.
  def test_newest_day_survives_an_entry_appended_at_the_bottom
    log = <<~MD
      # Update Log

      ## 2026-08-11
      * **Snapshot**: inbox 0 · in flight 1/5

      ## 2026-08-12
      * **Creation**: appended at the bottom, against convention.
    MD

    assert_equal "2026-08-12", OKF::Pro::Log.newest_day(log)
  end

  def test_newest_day_ignores_undated_headings
    assert_equal "2026-08-12", OKF::Pro::Log.newest_day("# Update Log\n\n## Notes\n\n## 2026-08-12\n")
  end

  # ── the line's shape ──────────────────────────────────────────────────────

  # Substring matching was a hole in both directions: a prose bullet posing
  # as the day's snapshot made the stop gate report twelve bogus
  # disagreements instead of its accurate missing-line refusal, and let the
  # audit pass CI on a mention with no real snapshot anywhere.
  def test_a_prose_mention_of_the_word_is_not_a_snapshot
    log = <<~MD
      # Update Log

      ## 2026-08-12
      - Rewrote the Snapshot checker end to end.
    MD

    refute OKF::Pro::Log.snapshot_under?(log, "2026-08-12")
  end

  def test_a_prose_mention_does_not_shadow_the_genuine_line_above_it
    log = <<~MD
      # Update Log

      ## 2026-08-12
      * **Snapshot**: inbox 1 · in flight 1/5
      - Note: the Snapshot line above was double-checked.
    MD

    assert_match(/inbox 1/, OKF::Pro::Log.snapshot_line(log, "2026-08-12"))
  end

  def test_accepted_shapes_bullet_and_bolding_optional
    [ "* **Snapshot**: inbox 0", "- Snapshot: inbox 0", "*   Snapshot : inbox 0" ].each do |line|
      assert OKF::Pro::Log.snapshot_under?("## 2026-08-12\n#{line}\n", "2026-08-12"), line
    end
  end

  def test_a_line_without_a_bullet_or_colon_is_not_a_snapshot
    [ "The Snapshot: was fine", "* Snapshot looked fine", "Snapshot: inbox 0" ].each do |line|
      refute OKF::Pro::Log.snapshot_under?("## 2026-08-12\n#{line}\n", "2026-08-12"), line
    end
  end

  # ── the banner's line ─────────────────────────────────────────────────────

  # Grepping the file and taking the last hit read the file's bottom — in a
  # newest-first log, the oldest entry: from day two onward the banner
  # reported the first-ever counters, inverting the delta it exists to show.
  def test_latest_snapshot_is_the_newest_days_line
    assert_match(/inbox 1/, OKF::Pro::Log.latest_snapshot_entry(LOG)[1])
  end

  def test_latest_snapshot_falls_back_to_an_older_day_when_the_newest_has_none
    log = <<~MD
      # Update Log

      ## 2026-08-12
      * **Creation**: no counters yet today.

      ## 2026-08-11
      * **Snapshot**: inbox 4 · in flight 1/5
    MD

    assert_match(/inbox 4/, OKF::Pro::Log.latest_snapshot_entry(log)[1])
  end

  def test_latest_snapshot_is_nil_on_a_dateless_log
    assert_nil OKF::Pro::Log.latest_snapshot_entry("# Update Log\n\nNothing dated yet.\n")[1]
  end

  # ── duplicate day headings ────────────────────────────────────────────────

  # The same date can head two blocks — two sessions in one day, or a merge —
  # and stopping at the first hid a snapshot the file held: the stop gate
  # refused "no Snapshot line under today" while one sat lower in the file.
  def test_a_snapshot_in_a_second_block_of_the_same_day_is_found
    log = <<~MD
      # Update Log

      ## 2026-08-12
      * **Creation**: the morning session.

      ## 2026-08-12
      * **Snapshot**: inbox 3 · in flight 1/5
    MD

    assert_match(/inbox 3/, OKF::Pro::Log.snapshot_line(log, "2026-08-12"))
    assert_match(/inbox 3/, OKF::Pro::Log.latest_snapshot_entry(log)[1])
  end

  # The file runs newest-first, so when the same day heads two blocks the
  # FIRST block holding a snapshot is the current one — taking the last in
  # file order handed a stale bottom copy (a merge leftover) to the gate
  # that verifies counters against today's board, refusing on a line the
  # owner had already corrected above it.
  def test_the_newest_first_block_wins_across_duplicate_days
    log = <<~MD
      ## 2026-08-12
      * **Snapshot**: inbox 2 · in flight 1/5 (the corrected line)

      ## 2026-08-11
      * **Snapshot**: inbox 9 · in flight 1/5

      ## 2026-08-12
      * **Snapshot**: inbox 1 · in flight 1/5 (stale, merged in below)
    MD

    assert_match(/inbox 2/, OKF::Pro::Log.snapshot_line(log, "2026-08-12"))
    assert_match(/inbox 2/, OKF::Pro::Log.latest_snapshot_entry(log)[1])
  end

  # The heading match is exact: a prefix test let a typo'd block answer
  # for the real day.
  def test_a_typo_heading_does_not_answer_for_the_real_day
    log = <<~MD
      ## 2026-08-123
      * **Snapshot**: inbox 5 · in flight 1/5

      ## 2026-08-12
      * **Creation**: the real day, no snapshot yet.
    MD

    assert_nil OKF::Pro::Log.snapshot_line(log, "2026-08-12")
  end

  # Both typo directions land in exactly one bucket: neither silently
  # adopted as a day nor silently dropped from the report.
  def test_every_typo_class_is_reported_not_silently_dropped
    log = "## 2026-8-12\n* x\n\n## 2026-08-123\n* x\n\n## 2026-08-32\n* x\n\n## Notes\n* x\n\n## 2026-08-11\n* **Snapshot**: inbox 0 · in flight 0/5\n"

    assert_equal [ "2026-08-11" ], OKF::Pro::Log.days(log)
    assert_equal [ "2026-8-12", "2026-08-123", "2026-08-32" ], OKF::Pro::Log.malformed_days(log)
  end

  # ── the calendar, not the string ──────────────────────────────────────────

  # A typo'd "## 2026-08-32" string-sorts above every real date, so it became
  # the "newest day" the audit interrogated — and its snapshot satisfied CI
  # while the genuine newest day carried none.
  def test_newest_day_rejects_a_date_the_calendar_rejects
    log = <<~MD
      ## 2026-08-32
      * **Snapshot**: inbox 0 · in flight 0/5

      ## 2026-08-12
      * **Creation**: the real newest day.
    MD

    assert_equal "2026-08-12", OKF::Pro::Log.newest_day(log)
    assert_equal [ "2026-08-32" ], OKF::Pro::Log.malformed_days(log)
  end

  def test_latest_snapshot_ignores_a_malformed_day
    log = "## 2026-13-01\n* **Snapshot**: inbox 7 · in flight 1/5\n\n## 2026-08-11\n* **Snapshot**: inbox 4 · in flight 1/5\n"

    assert_match(/inbox 4/, OKF::Pro::Log.latest_snapshot_entry(log)[1])
  end

  # Last-line-wins WITHIN the winning block, pinned through the banner's
  # own reader: a corrected line is appended below the stale one, and
  # flipping the iterator's assignment to first-wins would hand the banner
  # the superseded snapshot with every other test green.
  def test_the_banner_takes_the_corrected_line_within_the_newest_block
    log = <<~MD
      ## 2026-08-12
      * **Snapshot**: inbox 9 · in flight 1/5
      * **Snapshot**: inbox 3 · in flight 1/5 (corrected)

      ## 2026-08-11
      * **Snapshot**: inbox 1 · in flight 1/5
    MD

    assert_match(/inbox 3/, OKF::Pro::Log.latest_snapshot_entry(log)[1])
  end
end
