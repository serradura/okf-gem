# frozen_string_literal: true

require "test_helper"

# The counters against a real bundle, and the verifier against a drifted line.
# Derivation as a checker: everything here computes and compares; nothing here
# writes a line into anything.
class SnapshotTest < OKF::Pro::TestCase
  TODAY = Date.new(2026, 8, 12)
  BRIEFING_BODY = "# Summary\n\nAn agent read the source so nobody else had to. Yet.\n"

  def busy_bundle(b)
    b.concept("reference/movers-quote.md", type: "Briefing", body: BRIEFING_BODY,
      generated: { by: "claude", at: "2026-08-01" })
    b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
    b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")
    b.inbox("2026-08-01 — old capture, in the words it arrived in",
      "2026-08-10 — Resolve: [/reference/movers-quote.md] says X, the term says Y")
    b.board_lines("Waiting", "Landlord: inspection — asked 2026-08-01, chase 2026-08-05",
      "Plumber: quote — asked 2026-08-10, chase 2026-08-20")
    b.board_lines("Backlog", "sort out the storage unit")
    b.board_lines("To read", "[/reference/movers-quote.md] — agent-summarised, unread")
    b.board_lines("Deadlines",
      "2026-08-15 — insurance renewal lapses",
      "2026-08-14 — [/projects/home-move/](/projects/home-move/index.md) inventory due",
      "2026-10-01 — lease ends")
  end

  # THE INVARIANT, and it outranks what any single counter reads: the gate must
  # accept the line it prints as the remedy. A capture dated in the future
  # gives a negative age, `render` writes `oldest -365d`, and the pattern
  # demanded digits immediately after `oldest ` — so `parse` returned nil,
  # `verify` disagreed with the line it had just generated, and the refusal's
  # own suggested fix re-triggered the refusal. One mistyped year deadlocked
  # the Stop gate with no self-service exit.
  def test_the_line_it_recomputes_is_a_line_it_accepts
    with_bundle do |b|
      b.inbox("2027-08-12 — a capture with a mistyped year")
      root = b.bundle_path

      assert_empty OKF::Pro::Snapshot.verify(root, OKF::Pro::Snapshot.line(root, today: TODAY), today: TODAY)
    end
  end

  def test_a_future_dated_capture_round_trips_through_the_line
    with_bundle do |b|
      b.inbox("2027-08-12 — a capture with a mistyped year")
      counters = OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)

      assert_equal(-365, counters["oldest"])
      assert_equal(-365, OKF::Pro::Snapshot.parse(OKF::Pro::Snapshot.render(counters))["oldest"])
    end
  end

  def test_counts_the_whole_board
    with_bundle do |b|
      busy_bundle(b)
      c = OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)

      assert_equal 2, c["inbox"]
      assert_equal 11, c["oldest"]
      assert_equal 1, c["in flight"]
      assert_equal 5, c["cap"]
      assert_equal 2, c["waiting"]
      assert_equal 1, c["past chase"]
      assert_equal 1, c["backlog"]
      assert_equal 1, c["to read"]
      assert_equal 1, c["unverified briefings"]
      assert_equal 1, c["conflicts open"]
    end
  end

  # Crack 2's confession: due within 7 days and unpaired counts; due within 7
  # days but linked from an in-flight line does not; due in October does not.
  def test_deadlines_count_only_looming_and_uncovered
    with_bundle do |b|
      busy_bundle(b)

      assert_equal 1, OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)["deadlines within 7d not in flight"]
    end
  end

  def test_an_overdue_deadline_still_counts
    with_bundle do |b|
      b.board_lines("Deadlines", "2026-08-01 — already missed")

      assert_equal 1, OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)["deadlines within 7d not in flight"]
    end
  end

  # Work happening with no knowledge landing — the blind spot the structure
  # itself created. A closed project is not that: its extraction already ran.
  def test_counts_open_projects_holding_nothing_but_their_index
    with_bundle do |b|
      busy_bundle(b)
      b.write("projects/done/index.md", "# Done — closed 2026-08-01\n")

      assert_equal 1, OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)["projects with 0 concepts"]
    end
  end

  def test_a_project_with_a_concept_is_not_empty
    with_bundle do |b|
      b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
      b.concept("projects/home-move/plan.md", type: "Decision")
      b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — decide")

      assert_equal 0, OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)["projects with 0 concepts"]
    end
  end

  def test_an_empty_board_counts_all_zeros
    with_bundle do |b|
      c = OKF::Pro::Snapshot.counters(b.bundle_path, today: TODAY)

      assert(c.values.all? { |v| v.zero? || v == 5 }) # every counter 0, cap 5
      assert_equal 0, c["oldest"]
    end
  end

  # ── the verifier ──────────────────────────────────────────────────────────

  def test_a_true_line_verifies_clean
    with_bundle do |b|
      busy_bundle(b)
      root = b.bundle_path
      line = OKF::Pro::Snapshot.line(root, today: TODAY)

      assert_empty OKF::Pro::Snapshot.verify(root, line, today: TODAY)
    end
  end

  def test_a_drifted_line_is_named_field_by_field
    with_bundle do |b|
      busy_bundle(b)
      root = b.bundle_path
      wrong = OKF::Pro::Snapshot.line(root, today: TODAY).sub("inbox 2", "inbox 9")

      failure = OKF::Pro::Snapshot.verify(root, wrong, today: TODAY).first

      assert_match(/inbox is 2, the line says 9/, failure)
      assert_match(/recomputed:/, failure)
      refute_match(/waiting is/, failure)
    end
  end

  # The old vocabulary is not grandfathered: a line missing a field is a line
  # that cannot be compared with tomorrow's.
  def test_a_line_missing_a_field_fails_verification
    with_bundle do |b|
      busy_bundle(b)
      root = b.bundle_path

      failure = OKF::Pro::Snapshot.verify(root, "* **Snapshot**: inbox 2 (oldest 11d) · in flight 1/5",
        today: TODAY).first

      assert_match(/backlog is 1, the line says nothing/, failure)
    end
  end
end
