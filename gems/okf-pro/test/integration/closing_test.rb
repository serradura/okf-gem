# frozen_string_literal: true

require "test_helper"

# Rule 2. One of these refuses and one only informs, and that asymmetry is the
# rule itself: the snapshot is written at the end and read at the beginning.
class ClosingTest < OKF::Pro::TestCase
  TODAY = Date.new(2026, 8, 12)

  def worked_bundle(b)
    b.concept("glossary/term.md", type: "Term")
    b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
    b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")
  end

  # ── stop-gate ─────────────────────────────────────────────────────────────

  def test_passes_when_the_day_is_closed_properly
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.snapshot_on(TODAY.to_s)

      assert_empty OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY)
    end
  end

  def test_refuses_a_missing_snapshot
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something, but no counters.")

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY)

      assert_equal 1, refusal.size
      assert_match(/RULE 2/, refusal.first)
      assert_match(/no Snapshot line under 2026-08-12/, refusal.first)
    end
  end

  # The regression, end to end: yesterday's counters must not close today.
  def test_yesterdays_snapshot_does_not_close_today
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something.")
      b.log_day("2026-08-11", "* **Snapshot**: inbox 0 · in flight 1/5")

      assert_match(/no Snapshot line/, OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY).first)
    end
  end

  def test_reports_pairing_failures_alongside_the_snapshot
    with_bundle(git: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      b.write("projects/orphan/index.md", "# Orphan\n\nOngoing.\n")
      b.log_day(TODAY.to_s, "* **Creation**: something.")

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY).first

      assert_match(/no Snapshot line/, refusal)
      assert_match(%r{projects/orphan has no board line}, refusal)
    end
  end

  # The precondition is "work happened". A session that changed nothing owes
  # no snapshot, and asking for one would train people to write a line that
  # means nothing.
  def test_a_clean_tree_owes_nothing
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something, but no counters.")
      dir = b.path
      system("git", "-C", dir, "add", "-A", out: File::NULL, err: File::NULL)
      system("git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t",
        "commit", "-qm", "fixture", out: File::NULL, err: File::NULL)

      assert_empty OKF::Pro::Closing.stop_gate(event(cwd: dir), today: TODAY)
    end
  end

  # Without it, a refusal would re-enter the same gate that produced it.
  def test_a_continuation_is_not_re_gated
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: no counters.")

      assert_empty OKF::Pro::Closing.stop_gate(event(cwd: b.path, stop_hook_active: true), today: TODAY)
    end
  end

  def test_a_directory_without_a_board_is_not_this_gates_business
    Dir.mktmpdir do |dir|
      assert_empty OKF::Pro::Closing.stop_gate(event(cwd: dir), today: TODAY)
    end
  end

  # ── rooting through the cwd ───────────────────────────────────────────────

  # The gate's only input is the session's cwd, and resolve() neither walked
  # up nor discriminated: a subdirectory holding a directory index became a
  # bogus "broken core" refusal on every Stop, and one holding no index.md
  # silently disengaged the gate — the exact hole bundle_root.rb documents.
  def test_the_gate_holds_from_a_subdirectory_without_an_index
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something, but no counters.")
      dir = b.path
      notes = File.join(dir, "projects", "home-move", "notes")
      FileUtils.mkdir_p(notes)

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: notes), today: TODAY)

      assert_match(/no Snapshot line/, refusal.first)
    end
  end

  def test_a_directory_index_is_not_mistaken_for_a_broken_core
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something, but no counters.")
      dir = b.path

      refusal = OKF::Pro::Closing.stop_gate(
        event(cwd: File.join(dir, "projects", "home-move")), today: TODAY
      )

      assert_match(/no Snapshot line/, refusal.first)
      refute_match(/board\.md is missing/, refusal.first)
    end
  end

  # ── one parse per Stop ────────────────────────────────────────────────────

  # The gate runs on every Stop, and it used to parse every concept twice —
  # once for the snapshot's unverified count, once for pairing.
  def test_the_stop_gate_parses_the_bundle_once
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: no counters.")
      dir = b.path

      reads = 0
      reader = OKF::Bundle::Reader.singleton_class
      original = OKF::Bundle::Reader.method(:read)
      reader.send(:define_method, :read) { |root| reads += 1; original.call(root) }
      begin
        OKF::Pro::Closing.stop_gate(event(cwd: dir), today: TODAY)
      ensure
        reader.send(:define_method, :read, original)
      end

      assert_equal 1, reads
    end
  end

  # ── the board's date grammar, at the gate ─────────────────────────────────

  def test_refuses_a_dated_line_the_counters_cannot_read
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.board_lines("Deadlines", "Due Aug 18 — file the insurance claim")
      b.snapshot_on(TODAY.to_s)

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY)

      assert_match(/7-day warning cannot see it/, refusal.first)
    end
  end

  # ── session-context ───────────────────────────────────────────────────────

  def test_reports_the_counts_and_the_last_snapshot
    with_bundle do |b|
      b.in_flight("one", "two").inbox("a capture", "another")
      b.snapshot_on(TODAY.to_s)

      lines = OKF::Pro::Closing.session_context(event(cwd: b.path))

      assert_match(%r{\ABundle state at session start — in flight 2/5 }, lines[0])
      assert_match(/inbox 2 \(oldest 0d\)/, lines[0])
      assert_match(/\ALast snapshot \(#{TODAY}, not live\): \* \*\*Snapshot\*\*/, lines[2])
      assert_match(/Read the delta, not the status/, lines[3])
    end
  end

  # The regression: the log runs newest-first, and grepping the whole file
  # for the last hit read its bottom — the oldest entry. From day two onward
  # the banner reported the first-ever counters, inverting the delta.
  def test_the_banner_reports_the_newest_snapshot_not_the_oldest
    with_bundle do |b|
      b.in_flight("one")
      b.log_day("2026-08-10", "* **Snapshot**: inbox 9 (oldest 9d) · in flight 9/9")
      b.snapshot_on(TODAY.to_s)

      banner = OKF::Pro::Closing.session_context(event(cwd: b.path)).join("\n")

      assert_match(%r{^Last snapshot \(#{TODAY}, not live\): .*in flight 1/5}, banner)
      refute_match(/inbox 9/, banner)
    end
  end

  def test_the_banner_reaches_up_from_a_subdirectory
    with_bundle(git: true) do |b|
      b.in_flight("one")
      dir = b.path
      notes = File.join(dir, "projects", "x", "notes")
      FileUtils.mkdir_p(notes)

      lines = OKF::Pro::Closing.session_context(event(cwd: notes))

      assert_match(%r{in flight 1/5}, lines[0])
    end
  end

  def test_says_so_when_there_is_no_snapshot_yet
    with_bundle do |b|
      b.in_flight("one")

      assert_match(/Last snapshot: none yet/, OKF::Pro::Closing.session_context(event(cwd: b.path))[2])
    end
  end

  def test_returns_nothing_outside_a_bundle
    Dir.mktmpdir do |dir|
      assert_nil OKF::Pro::Closing.session_context(event(cwd: dir))
    end
  end
  # ── the stop gate verifies, not just detects ──────────────────────────────

  # Presence was never the point; agreement is. And the refusal carries the
  # recomputed line, because the fix is a paste.
  def test_refuses_a_snapshot_that_disagrees_with_the_board
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Snapshot**: inbox 7 (oldest 3d) · in flight 2/5 · waiting 0 (0 past chase) " \
                            "· backlog 0 · to read 0 · unverified briefings 0 · conflicts open 0 " \
                            "· deadlines within 7d not in flight 0 · projects with 0 concepts 1")

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY).first

      assert_match(/RULE 2/, refusal)
      assert_match(/disagrees with the bundle/, refusal)
      assert_match(/inbox is 0, the line says 7/, refusal)
      assert_match(/recomputed:/, refusal)
    end
  end

  def test_the_missing_snapshot_refusal_carries_the_computed_line
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something, but no counters.")

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: b.path), today: TODAY).first

      assert_match(/computed from the bundle as it stands/, refusal)
      assert_match(/\* \*\*Snapshot\*\*: inbox 0/, refusal)
    end
  end

  # ── what the session banner injects ───────────────────────────────────────

  def test_injects_looming_uncovered_deadlines
    with_bundle do |b|
      worked_bundle(b)
      b.board_lines("Deadlines", "2026-08-14 — insurance renewal lapses")

      lines = OKF::Pro::Closing.session_context(event(cwd: b.path), today: TODAY)

      assert(lines.any? { |l| l.include?("Deadlines within 7d with nothing in flight") })
      assert(lines.any? { |l| l.include?("insurance renewal lapses") })
    end
  end

  def test_a_covered_deadline_is_not_injected
    with_bundle do |b|
      worked_bundle(b)
      b.board_lines("Deadlines", "2026-08-14 — [/projects/home-move/](/projects/home-move/index.md) inventory due")

      lines = OKF::Pro::Closing.session_context(event(cwd: b.path), today: TODAY)

      refute(lines.any? { |l| l.include?("Deadlines within 7d") })
    end
  end

  def test_injects_the_dormancy_question
    with_bundle do |b|
      worked_bundle(b)
      b.write("journal/2026-08-01.md", "---\ntype: Journal Entry\ntitle: A day\ndescription: Fixture.\n---\n\nOld enough.\n")
      b.write("journal/2026-08-10.md", "---\ntype: Journal Entry\ntitle: A day\ndescription: Fixture.\n---\n\nAbout other things.\n")

      lines = OKF::Pro::Closing.session_context(event(cwd: b.path), today: TODAY)

      assert(lines.any? { |l| l.include?("dormancy") && l.include?("/projects/home-move/") })
    end
  end

  # A bundle missing its skeleton used to slip the gate in silence — the
  # exist-check read as "not my business" when it was the whole business.
  def test_a_broken_core_refuses_instead_of_disengaging
    with_bundle(git: true) do |b|
      worked_bundle(b)
      b.log_day(TODAY.to_s, "* **Creation**: something.")
      dir = b.path
      File.delete(File.join(dir, "board.md"))

      refusal = OKF::Pro::Closing.stop_gate(event(cwd: dir), today: TODAY)

      assert_equal 1, refusal.size
      assert_match(/board\.md is missing/, refusal.first)
      assert_match(/only roadmap\.md is deletable/, refusal.first)
    end
  end

  def test_session_context_says_the_core_is_broken
    with_bundle do |b|
      worked_bundle(b)
      dir = b.path
      File.delete(File.join(dir, "log.md"))

      lines = OKF::Pro::Closing.session_context(event(cwd: dir), today: TODAY)

      assert(lines.any? { |l| l.include?("broken core") })
      assert(lines.any? { |l| l.include?("log.md is missing") })
    end
  end
end
