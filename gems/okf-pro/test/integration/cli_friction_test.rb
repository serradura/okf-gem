# frozen_string_literal: true

require "test_helper"

# `okf pro friction` — report-only, exit 0, the family `unverified` belongs to.
#
# It measures this gem rather than the adopter's bundle: which shape of edit is
# still being done by hand because no verb covers it. A measurement that gated
# something would start being gamed the day someone noticed, so it gates
# nothing — and nothing is ever filed automatically.
class CLIFrictionTest < OKF::Pro::TestCase
  def record(b, via, what, detail = nil)
    OKF::Pro::Friction.record(b.bundle_path, via, what, detail)
  end

  test "an empty recorder reports nothing and exits 0" do
    with_bundle do |b|
      run = run_cli([ "friction", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_empty run.err
      assert_match(/nothing recorded/, run.out)
    end
  end

  # Grouped by the DOOR as well as the file: an Edit to the board and a shell
  # redirect at it are different findings about the same path, and what covers
  # them is not the same answer.
  test "recorded events are grouped by the door and the file" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      record(b, "edit", "board.md")
      record(b, "shell", "board.md")
      run = run_cli([ "friction", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/3 bundle edit\(s\) recorded so far/, run.out)
      assert_match(/^\s+edit board\.md\s+2\s+now: okf pro capture/, run.out)
      assert_match(/^\s+shell board\.md\s+1\s+now: Edit or Write/, run.out)
    end
  end

  # The report's job is to answer "which verb is missing", so it says what
  # already covers each row — that is how the question keeps being answered
  # rather than asked once.
  test "an edit to the board names the verbs that cover it" do
    with_bundle do |b|
      record(b, "edit", "board.md")

      assert_match(%r{okf pro capture / promote / demote}, run_cli([ "friction", b.path ]).out)
    end
  end

  # A shell write is a bypass whatever it touched: the trust guards read a tool
  # event and a redirect is none. So the answer is Edit or Write, never a verb.
  test "a shell write points at the tools the guards can see" do
    with_bundle do |b|
      record(b, "shell", "unclassified", "mv a.md b.md")
      out = run_cli([ "friction", b.path ]).out

      assert_match(/^\s+shell unclassified\s+1\s+now: Edit or Write/, out)
      refute_match(/okf pro capture/, out)
    end
  end

  # The count is a lifetime total on an append-only log, so the line that
  # frames it has to say so — and has to name the way out, or it nags forever
  # about a week nobody can change.
  test "the report says the count is cumulative and how to reset it" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      out = run_cli([ "friction", b.path ]).out

      assert_match(/recorded so far/, out)
      assert_match(/`okf pro friction --clear` starts it again/, out)
    end
  end

  test "the report addresses the adopter and points at the issue flag" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      out = run_cli([ "friction", b.path ]).out

      assert_match(/please tell the maintainer/, out)
      assert_match(/`okf pro friction --issue`/, out)
    end
  end

  # ── the data-unavailable path ───────────────────────────────────────────
  #
  # A count of zero and "the recorder could not write" are different states,
  # and confusing them retires the measurement in silence.

  test "an unavailable recorder says the number is unknown, not zero" do
    with_bundle do |b|
      path = b.path
      File.write(File.join(OKF::Pro::Friction.scratch_root(b.bundle_path), ".tmp"), "not a directory")
      run = run_cli([ "friction", path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/the recorder could not write/, run.out)
      refute_match(/nothing recorded/, run.out)
    end
  end

  # The marker is sticky on purpose — one failed write means the count is short
  # by an unknown amount forever after — so "check that .tmp/ is writable" is
  # not actionable on its own: the directory may be perfectly writable now and
  # the answer still unknown, which is correct and infuriating without the next
  # sentence.
  test "the unavailable message names the way back to a countable state" do
    with_bundle do |b|
      OKF::Pro::Friction.mark_unavailable(b.bundle_path)

      assert_match(/`okf pro friction --clear`/, run_cli([ "friction", b.path ]).out)
    end
  end

  test "--clear removes the log and the marker and the count starts again" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      OKF::Pro::Friction.mark_unavailable(b.bundle_path)
      path = b.path
      run = run_cli([ "friction", path, "--clear" ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/cleared \(2 file\(s\) removed\)/, run.out)
      assert_match(/nothing recorded/, run_cli([ "friction", path ]).out)
    end
  end

  # Even the reset says what it could not do. A clear that failed and reported
  # success would leave the reader believing a stuck marker was gone.
  test "a clear that cannot remove the files names them instead of claiming success" do
    with_bundle do |b|
      path = b.path
      FileUtils.mkdir_p(OKF::Pro::Friction.log_path(b.bundle_path))
      run = run_cli([ "friction", path, "--clear" ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/could not clear/, run.out)
      assert_match(/okf-pro-friction\.log/, run.out)
      refute_match(/cleared \(/, run.out)
    end
  end

  # It touches `.tmp/` and nothing else — this is telemetry, not knowledge.
  test "--clear touches nothing inside the bundle" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      path = b.path
      before = Dir.glob(File.join(b.bundle_path, "**", "*.md")).sort.map { |f| [ f, OKF::Pro.read_text(f) ] }
      run_cli([ "friction", path, "--clear" ])

      assert_equal before, Dir.glob(File.join(b.bundle_path, "**", "*.md")).sort.map { |f| [ f, OKF::Pro.read_text(f) ] }
    end
  end

  test "unreadable lines are confessed rather than dropped from the count" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      File.open(OKF::Pro::Friction.log_path(b.bundle_path), "a") { |f| f.puts "{not json" }

      assert_match(/1 recorded line\(s\) could not be parsed/, run_cli([ "friction", b.path ]).out)
    end
  end

  # ── --json ──────────────────────────────────────────────────────────────

  test "--json carries the availability alongside the rows" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      record(b, "shell", "log.md")
      payload = JSON.parse(run_cli([ "friction", b.path, "--json" ]).out)

      assert payload["available"]
      assert_equal 2, payload["recorded"]
      assert_equal 0, payload["unreadable"]

      edit = payload["by"].find { |row| row["via"] == "edit" }

      assert_equal "board.md", edit["what"]
      assert_equal 1, edit["count"]
      assert_match(/okf pro capture/, edit["covered by"])
    end
  end

  test "--pretty is --json, indented" do
    with_bundle do |b|
      run = run_cli([ "friction", b.path, "--pretty" ])

      assert_match(/\A\{\n  "available"/, run.out)
    end
  end

  # ── --issue ─────────────────────────────────────────────────────────────
  #
  # Printed, never run. Filing an issue is outward-facing and irreversible, and
  # a hook that did it unattended would be both without anyone asking.

  def with_path_holding(gh:)
    Dir.mktmpdir do |bin|
      if gh
        File.write(File.join(bin, "gh"), "#!/bin/sh\nexit 0\n")
        File.chmod(0o755, File.join(bin, "gh"))
      end
      original = ENV.fetch("PATH", nil)
      ENV["PATH"] = bin
      begin
        yield
      ensure
        ENV["PATH"] = original
      end
    end
  end

  test "--issue prints a gh command when gh is on PATH, and does not run it" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      path = b.path
      with_path_holding(gh: true) do
        run = run_cli([ "friction", path, "--issue" ])

        assert_equal OKF::Pro::PASS, run.status
        assert_match(/it is not run for you/, run.out)
        assert_match(%r{gh issue create --repo serradura/okf}, run.out)
        assert_match(/--title 'okf-pro: 1 bundle edit/, run.out)
        assert_match(/covered by: okf pro capture/, run.out)
      end
    end
  end

  test "--issue prints the URL and the body when gh is absent" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      path = b.path
      with_path_holding(gh: false) do
        run = run_cli([ "friction", path, "--issue" ])

        assert_equal OKF::Pro::PASS, run.status
        assert_match(/`gh` is not on PATH/, run.out)
        assert_match(%r{https://github\.com/serradura/okf/issues/new}, run.out)
        assert_match(/^Title: okf-pro: 1 bundle edit/, run.out)
        refute_match(/gh issue create/, run.out)
      end
    end
  end

  test "--issue says so when the counts are unknown rather than reporting none" do
    with_bundle do |b|
      path = b.path
      File.write(File.join(OKF::Pro::Friction.scratch_root(b.bundle_path), ".tmp"), "not a directory")
      with_path_holding(gh: false) do
        assert_match(/could not write at some point, so this is a floor rather than a total/,
          run_cli([ "friction", path, "--issue" ]).out)
      end
    end
  end

  # A marker suppresses the NUMBER, not the evidence. The body dropped every row
  # it had and then said "the counts above are unknown" over a body that had no
  # counts in it — a sentence about text that was not there.
  test "--issue keeps the rows it did record when the recorder degraded" do
    with_bundle do |b|
      record(b, "edit", "board.md")
      OKF::Pro::Friction.mark_unavailable(b.bundle_path)
      with_path_holding(gh: false) do
        out = run_cli([ "friction", "--issue", b.path ]).out

        assert_match(/`edit board\.md` — 1 time\(s\)/, out)
        assert_match(/could not write at some point/, out)
        refute_match(/counts above are unknown/, out)
      end
    end
  end

  # Quoting the body for a shell the reader will paste it into. The body is
  # assembled from this gem's own vocabulary, which is exactly the place not to
  # assume that stays true — so the quoting is asked of a real shell rather
  # than eyeballed.
  test "the quoting survives a real shell, apostrophes and all" do
    [ "plain", "it's a detail", "a 'quoted' thing", "'", "$(echo pwned)", "a\nb" ].each do |text|
      quoted = OKF::Pro::CLI.shell_quote(text)
      back = IO.popen([ "sh", "-c", "printf %s #{quoted}" ], &:read)

      assert_equal text, back, "#{text.inspect} does not survive #{quoted}"
    end
  end

  # A report whose whole content is "0 event(s)" is a report nobody should
  # paste. The unavailable case below is different and stays: "the recorder
  # could not write" is a thing that happened.
  test "--issue with nothing recorded prints no issue at all" do
    with_bundle do |b|
      run = run_cli([ "friction", "--issue", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      refute_match(/gh issue create/, run.out)
      refute_match(%r{issues/new}, run.out)
      assert_match(/nothing recorded/, run.out)
    end
  end

  # Zero parseable rows is not "nothing recorded" when the log holds lines
  # nobody could parse: that is a corrupted recorder, and it is precisely what
  # the maintainer needs told.
  test "--issue still files when every recorded line was unparseable" do
    with_bundle do |b|
      path = b.path
      log = OKF::Pro::Friction.log_path(b.bundle_path)
      FileUtils.mkdir_p(File.dirname(log))
      File.write(log, "not json\n{\"half\":\n")
      with_path_holding(gh: false) do
        out = run_cli([ "friction", "--issue", path ]).out

        refute_match(/nothing recorded/, out)
        assert_match(/2 recorded line\(s\) were unparseable/, out)
      end
    end
  end

  # The title is what a maintainer triages on, and the banner had just
  # established that a shell redirect is covered by Edit or Write rather than
  # by a verb. A title claiming otherwise asks for a verb this gem decided not
  # to want.
  test "the issue title does not claim a verb covers what no verb covers" do
    with_bundle do |b|
      record(b, "shell", "board.md", "cat notes.md > .okf/board.md")
      with_path_holding(gh: false) do
        out = run_cli([ "friction", "--issue", b.path ]).out

        refute_match(/that a verb could cover/, out)
        assert_match(/^Title: okf-pro: 1 bundle edit\(s\) recorded by hand/, out)
      end
    end
  end

  # `--issue` calls this state a corrupted recorder and files for it, so the
  # human default may not call the same log "nothing recorded" — that would make
  # the default surface the one that lies.
  test "the default report confesses a log it could not read at all" do
    with_bundle do |b|
      log = OKF::Pro::Friction.log_path(b.bundle_path)
      FileUtils.mkdir_p(File.dirname(log))
      File.write(log, "not json\n{\"half\":\n")
      out = run_cli([ "friction", b.path ]).out

      refute_match(/nothing recorded/, out)
      assert_match(/2 recorded line\(s\)/, out)
    end
  end

  # ── addressing and the exits ────────────────────────────────────────────

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "friction", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "an unknown flag is a usage error" do
    with_bundle do |b|
      run = run_cli([ "friction", b.path, "--full" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/invalid option: --full/, run.err)
    end
  end

  test "friction emits no enforcer marker" do
    with_bundle do |b|
      refute run_cli([ "friction", b.path ]).identified?
    end
  end
end
