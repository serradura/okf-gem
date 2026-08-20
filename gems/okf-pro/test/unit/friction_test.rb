# frozen_string_literal: true

require "test_helper"

# The recorder — the one thing here that is neither a gate nor a report.
#
# Its contract is the contract's third clause applied to telemetry: it neither
# refuses nor blocks, but it does not lie about having counted. A count of zero
# and "the recorder could not write" are different states, and the whole value
# of the measurement dies the day they are confused.
class FrictionTest < OKF::Pro::TestCase
  Friction = OKF::Pro::Friction

  # ── where it writes ─────────────────────────────────────────────────────
  #
  # The repository root, not the bundle: this is telemetry ABOUT the bundle and
  # not knowledge IN it, `okf validate` walks every `.md` under the root, and
  # the seeded `.gitignore` already ignores `.tmp/` at the top.

  test "a nested bundle records into the repository's scratch directory" do
    with_bundle(nested: true) do |b|
      Friction.record(b.bundle_path, "edit", "board.md")

      assert File.file?(File.join(b.path, ".tmp", "okf-pro-friction.log"))
      refute File.exist?(File.join(b.bundle_path, ".tmp", "okf-pro-friction.log"))
    end
  end

  test "a flat bundle records beside itself, because it is the repository" do
    with_bundle do |b|
      Friction.record(b.path, "edit", "board.md")

      assert File.file?(File.join(b.path, ".tmp", "okf-pro-friction.log"))
    end
  end

  # ── what it records ─────────────────────────────────────────────────────

  test "one event per record, read back in file order" do
    with_bundle do |b|
      Friction.record(b.path, "edit", "board.md", "board.md", today: Date.new(2026, 8, 17))
      Friction.record(b.path, "shell", "log.md", "echo x >> .okf/log.md", today: Date.new(2026, 8, 17))

      report = Friction.report(b.path)

      assert report.available
      assert_equal %w[board.md log.md], report.events.map { |e| e["what"] }
      assert_equal "2026-08-17", report.events.first["at"]
      assert_equal 0, report.unreadable
    end
  end

  # A line that will not parse is counted, never dropped. Dropping it would
  # make a corrupted log read as a quieter session.
  test "an unparseable line is counted rather than silently skipped" do
    with_bundle do |b|
      Friction.record(b.path, "edit", "board.md")
      File.open(Friction.log_path(b.path), "a") { |f| f.puts "{not json" }

      report = Friction.report(b.path)

      assert_equal 1, report.events.size
      assert_equal 1, report.unreadable
    end
  end

  test "no log at all is an available zero, not an unavailable one" do
    with_bundle do |b|
      report = Friction.report(b.path)

      assert report.available
      assert_empty report.events
    end
  end

  # ── the unavailable path ────────────────────────────────────────────────

  test "a failed write leaves a marker and the report says unavailable" do
    with_bundle do |b|
      # A file where the scratch directory should be: mkdir_p raises, and the
      # marker cannot be written for the same reason — which is exactly why
      # `available?` asks the directory rather than trusting the marker alone.
      File.write(File.join(b.path, ".tmp"), "not a directory")

      refute Friction.record(b.path, "edit", "board.md")
      refute Friction.report(b.path).available
    end
  end

  test "a marker on its own is enough to make the count unknown" do
    with_bundle do |b|
      Friction.record(b.path, "edit", "board.md")
      Friction.mark_unavailable(b.path)

      report = Friction.report(b.path)

      refute report.available, "one failed write makes the whole count unknown, not short by one"
      assert_equal 1, report.events.size
    end
  end

  # A root the filesystem cannot even be asked about must answer "unknown"
  # rather than raise: the callers are a PreToolUse guard and a PostToolUse
  # check, and an exception out of either is an edit sailing through while the
  # gate lies on the floor.
  test "a root the filesystem rejects answers unknown rather than raising" do
    report = Friction.report("bad\0root")

    refute report.available
    assert_empty report.events
    refute Friction.available?("bad\0root")
  end

  test "a record against an impossible root fails quietly and returns false" do
    refute Friction.record("bad\0root", "edit", "board.md")
  end

  # ── the predicates ──────────────────────────────────────────────────────
  #
  # The good path must not count as friction, or the recorder reports the verbs
  # being used as evidence that they are missing.

  # Asked of ONE segment, and anchored to its start: this answers "is this an
  # invocation of the gem?", not "is the gem mentioned?". `ShellGuard.own_write?`
  # does the splitting, and its tests carry the compound shapes.
  test "an okf pro invocation is not friction" do
    assert Friction.own_command?("okf pro capture \"a thing\"")
    assert Friction.own_command?(" okf  pro promote alpha")
    refute Friction.own_command?("echo x >> .okf/board.md")
    refute Friction.own_command?("okf validate .okf")
    refute Friction.own_command?('echo "- see okf pro docs" >> .okf/board.md'),
      "the gem's name in a board line's text is not an invocation of it"
  end

  # The board, and only the board — and the exclusions are the point.
  #
  # `snapshot` deliberately has no `--write`, so appending the Snapshot line to
  # `log.md` by hand is the PRESCRIBED path; `journal open` says in as many
  # words that the day's content is yours. Counting either records the system
  # working as evidence that it does not, which is the same mistake
  # `own_command?` exists to prevent, one layer up.
  test "only the board counts as an Edit worth recording" do
    assert Friction.covered_path?("board.md")
    refute Friction.covered_path?("log.md"), "appending the Snapshot line by hand is what this gem asks for"
    refute Friction.covered_path?("journal/2026-08-17.md"), "the day's content is the writer's, by design"
    refute Friction.covered_path?("reference/a-briefing.md")
    refute Friction.covered_path?("journal/index.md")
    refute Friction.covered_path?("projects/alpha/board.md"), "somebody's notes are not the one page Rule 3 counts"
    refute Friction.covered_path?(nil)
  end

  # A shell command has no file_path — that is why shell-guard exists — so the
  # class is read out of the command, and "shell" is the honest answer when it
  # cannot be told.
  test "a command records as the class it names, or as unclassified when it names none" do
    assert_equal "board.md", Friction.classify_command("cat x >> .okf/board.md")
    assert_equal "log.md", Friction.classify_command("sed -i '' s/a/b/ .okf/log.md")
    assert_equal "journal", Friction.classify_command("cp a .okf/journal/2026-08-17.md")
    assert_equal "unclassified", Friction.classify_command("mv .okf/reference/a.md .okf/reference/b.md")
  end

  # The two doors mean different things about the same file. An Edit to the
  # board says a verb went unused; a shell redirect at anything says the trust
  # guards were bypassed, because they read a tool event and a redirect is
  # none. What covers those is not the same answer.
  test "what covers a row depends on the door as much as the file" do
    assert_match(/okf pro capture/, Friction.covered_by("edit", "board.md"))
    assert_match(/Edit or Write/, Friction.covered_by("shell", "board.md"))
    assert_match(/Edit or Write/, Friction.covered_by("shell", "unclassified"))
    assert_nil Friction.covered_by("edit", "unclassified"),
      "an unattributed edit must not claim a verb covers it"
  end

  # Sticky is correct — one failed write means the count is short by an unknown
  # amount forever after — but sticky with no way out is a report that nags
  # permanently about a full disk from three weeks ago.
  test "clear removes the log and the marker, and the report recovers" do
    with_bundle do |b|
      Friction.record(b.path, "edit", "board.md")
      Friction.mark_unavailable(b.path)

      refute Friction.report(b.path).available

      assert_equal 2, Friction.clear(b.path)

      report = Friction.report(b.path)

      assert report.available
      assert_empty report.events
    end
  end

  test "clearing an already-clean recorder removes nothing and still succeeds" do
    with_bundle do |b|
      assert_equal 0, Friction.clear(b.path)
    end
  end

  test "clear answers nil rather than raising when it cannot remove anything" do
    assert_nil Friction.clear("bad\0root")
  end
end
