# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Dispatch and exit codes. The hook protocol reads 0 and 2 and nothing else:
# every other code is a non-blocking error, which means the edit proceeds. So
# every test here is really asking the same thing — when this checker cannot
# do its job, does it return 2, or does it return something that lets the
# write through while looking like it ran?
class CLITest < OKF::Pro::TestCase
  def bundle_event(dir, rel, **attrs)
    JSON.generate(stringify({ cwd: dir, tool_input: { file_path: File.join(dir, rel) } }.merge(attrs)))
  end

  # ── the codes ─────────────────────────────────────────────────────────────

  def test_a_passing_check_returns_zero_and_says_nothing
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      run = run_cli(%w[check-okf], stdin: bundle_event(b.path, "glossary/term.md"))

      assert_equal OKF::Pro::PASS, run.status
      assert_empty run.findings
    end
  end

  def test_a_refusal_returns_two_and_explains
    with_bundle do |b|
      b.raw("glossary/broken.md", "# Broken\n\nNo frontmatter.\n")
      run = run_cli(%w[check-okf], stdin: bundle_event(b.path, "glossary/broken.md"))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/okf validate failed/, run.err)
    end
  end

  # The hole this whole checker exists to close: an unreadable event used to
  # read as an innocent one.
  def test_unparseable_input_refuses
    run = run_cli(%w[guard-verified], stdin: "{not json")

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/ENFORCEMENT DEGRADED/, run.err)
    assert_match(/No check ran/, run.err)
  end

  def test_empty_input_refuses
    run = run_cli(%w[guard-verified], stdin: "")

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/no event on stdin/, run.err)
  end

  # The shell dispatcher fell off the end of its `case` on a typo and exited 0
  # — enforcement switched off by a misspelling, in silence.
  def test_an_unknown_check_refuses
    run = run_cli(%w[nonesuch], stdin: "{}")

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/ENFORCEMENT MISCONFIGURED/, run.err)
    assert_match(/no check named 'nonesuch'/, run.err)
  end

  def test_no_check_name_refuses
    assert_equal OKF::Pro::BLOCK, run_cli([], stdin: "{}").status
  end

  def test_the_error_names_every_check_that_does_exist
    run = run_cli(%w[nope], stdin: "{}")

    OKF::Pro::CLI::NAMES.each { |name| assert_match(/#{Regexp.escape(name)}/, run.err) }
  end

  # ── routing ───────────────────────────────────────────────────────────────

  # Exit 0 plus the ask JSON: the hook protocol routes the decision to the
  # owner. Interactive, a prompt; unattended, no approver — fails closed at
  # the permission layer, which is the floor the old outright denial had.
  def test_guard_verified_asks_the_owner_end_to_end
    with_bundle(nested: true) do |b|
      run = run_cli(%w[guard-verified],
        stdin: JSON.generate(stringify(
          cwd: b.path,
          tool_input: { file_path: File.join(b.path, ".okf/x.md"),
                        new_string: "verified: yes" }
        )))

      assert_equal OKF::Pro::PASS, run.status
      assert_empty run.findings
      decision = JSON.parse(run.out)["hookSpecificOutput"]
      assert_equal "PreToolUse", decision["hookEventName"]
      assert_equal "ask", decision["permissionDecision"]
      assert_match(/owner attestation/, decision["permissionDecisionReason"])
    end
  end

  def test_a_clean_edit_through_guard_verified_stays_silent
    run = run_cli(%w[guard-verified],
      stdin: JSON.generate("tool_input" => { "file_path" => "/b/x.md",
                                             "new_string" => "nothing attested here" }))

    assert_equal OKF::Pro::PASS, run.status
    assert_empty run.out
    assert_empty run.findings
  end

  def test_post_edit_runs_all_three_post_checks
    with_bundle do |b|
      b.concept("glossary/binding-estimate.md", type: "Term",
        body: "# Definition\n\nA binding estimate fixes the listed price.\n")
      run = run_cli(%w[post-edit],
        stdin: bundle_event(b.path, "reference/binding-estimate-notes.md",
          tool_name: "Write"))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/RULE 1 — reconciliation/, run.err)
    end
  end

  def test_post_edit_reports_conformance_and_reconciliation_together
    with_bundle do |b|
      b.concept("glossary/binding-estimate.md", type: "Term",
        body: "# Definition\n\nA binding estimate fixes the listed price.\n")
      dir = b.path
      FileUtils.mkdir_p(File.join(dir, "reference"))
      File.write(File.join(dir, "reference", "binding-estimate-notes.md"), "# No frontmatter\n")
      run = run_cli(%w[post-edit],
        stdin: bundle_event(dir, "reference/binding-estimate-notes.md", tool_name: "Write"))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/okf validate failed/, run.err)
      assert_match(/RULE 1/, run.err)
    end
  end

  # The edit door, end to end. `covered_path?` admits exactly one path, so what
  # a row records as IS that path — and the only proof that the guard and the
  # recorder are wired to each other is a real event going through both.
  def test_post_edit_records_a_hand_edit_of_the_board_as_friction
    with_bundle do |b|
      run_cli(%w[post-edit], stdin: bundle_event(b.path, "board.md", tool_name: "Edit"))
      event = OKF::Pro::Friction.report(b.bundle_path).events.first

      refute_nil event, "the edit door recorded nothing"
      assert_equal [ "edit", "board.md" ], [ event["via"], event["what"] ]
    end
  end

  # The exclusions are the measurement. An Edit to a concept body is judgment
  # and always will be, and counting it would point the maintainer at a verb
  # nobody should write.
  def test_post_edit_records_nothing_for_an_edit_no_verb_covers
    with_bundle do |b|
      run_cli(%w[post-edit], stdin: bundle_event(b.path, "areas/corpus.md", tool_name: "Edit"))

      assert_empty OKF::Pro::Friction.report(b.bundle_path).events
    end
  end

  # ── the two that do not refuse ────────────────────────────────────────────

  def test_session_context_prints_to_stdout_and_passes
    with_bundle do |b|
      b.in_flight("one").snapshot_on("2026-08-12")
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path))

      assert_equal OKF::Pro::PASS, run.status
      assert_match(%r{in flight 1/5}, run.out)
      assert_empty run.findings
    end
  end

  # The structured block, and the reason it is in the banner rather than behind
  # a verb: the bill is turns × context, and state delivered at SessionStart
  # costs no turn at all. Its contract is that it stays CHEAP — nothing here
  # parses a concept — and that the two counters it cannot compute cheaply are
  # labelled by the day they were logged rather than presented as live.
  def test_the_session_banner_carries_the_structured_state_block
    with_bundle do |b|
      b.in_flight("one").inbox("a capture").snapshot_on("2026-08-12")
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path))

      assert_match(/^Bundle state at session start — in flight 1\/5 · backlog 0 · waiting 0 \(0 past chase\)/, run.out)
      # The banner's promise is that it says what the verb says: one renderer,
      # asserted as one, so a second copy cannot appear and drift.
      state = run_cli([ "state", b.path ]).out.lines.first.sub("Board —", "Bundle state at session start —")

      assert_includes run.out, state
      assert_match(/^Log — newest day 2026-08-12 · journal for #{Date.today} not opened · open projects 0$/, run.out)
      assert_match(/^Last snapshot \(2026-08-12, not live\): \* \*\*Snapshot\*\*: /, run.out)
    end
  end

  # The line that actually saves the turns: without it the banner is state an
  # agent re-reads from the files the moment it writes anything.
  def test_the_banner_says_how_to_refresh_instead_of_re_reading
    with_bundle do |b|
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path))

      assert_match(/refresh with `okf pro state` — do not re-read the files/, run.out)
      assert_match(/`okf pro capture`/, run.out)
    end
  end

  # A day-zero bundle has no snapshot to parse, and the block must not invent
  # one — `scaffold_test` pins that the same bundle produces no friction line
  # either, so the banner of a fresh bundle says only what is true of it.
  def test_the_banner_omits_the_snapshot_block_when_there_is_no_snapshot
    with_bundle do |b|
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path))

      refute_match(/not live/, run.out)
      refute_match(/done by hand/, run.out)
    end
  end

  def test_the_banner_reports_todays_journal_as_open_once_it_exists
    with_bundle do |b|
      dir = b.path
      File.write(File.join(dir, "journal", "#{Date.today}.md"),
        "---\ntype: Journal Entry\ntitle: today\ndescription: The day.\n---\n\n# Today\n")
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => dir))

      assert_match(/journal for #{Date.today} open ·/, run.out)
    end
  end

  # A recorded bypass reaches the adopter here, phrased as a request rather
  # than a reprimand: they are the ones paying for a missing verb and the only
  # ones who can say which one it is.
  def test_the_banner_reports_recorded_friction_to_the_adopter
    with_bundle do |b|
      OKF::Pro::Friction.record(b.bundle_path, "edit", "board.md")
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path))

      assert_match(/1 bundle edit\(s\) so far were done by hand/, run.out)
      assert_match(/`okf pro friction --issue`/, run.out)
      assert_match(/`--clear` resets the count/, run.out)
    end
  end

  # A count of zero and "the recorder could not write" are different states,
  # and the banner is the one place confusing them would retire the
  # measurement in silence.
  def test_the_banner_says_unknown_rather_than_zero_when_the_recorder_failed
    with_bundle do |b|
      File.write(File.join(OKF::Pro::Friction.scratch_root(b.bundle_path), ".tmp"), "not a directory")
      run = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path))

      assert_match(/unknown rather than zero/, run.out)
      assert_match(/`okf pro friction --clear`/, run.out)
    end
  end

  # SessionStart has no blocking channel, so this one says what it could not
  # do and lets the session start. It is the single exception, and it is an
  # exception because refusing would achieve nothing.
  def test_session_context_degrades_rather_than_refusing
    run = run_cli(%w[session-context], stdin: "{not json")

    assert_equal OKF::Pro::PASS, run.status
    assert_match(/Bundle state unavailable/, run.out)
    assert_match(/The gates still run/, run.out)
  end

  def test_audit_passes_on_a_clean_bundle
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")
      run = run_cli([ "audit", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/audit — clean/, run.out)
    end
  end

  # audit is not a hook, so it speaks CI's exit codes rather than the hook
  # protocol's: 1, not 2.
  def test_audit_fails_with_cis_exit_code
    with_bundle do |b|
      b.raw("glossary/broken.md", "# Broken\n\nNo frontmatter.\n")
      b.snapshot_on("2026-08-12")
      run = run_cli([ "audit", b.path ])

      assert_equal OKF::Pro::FAIL, run.status
      assert_match(/1 finding/, run.err)
    end
  end

  # Exit 2, not 1, and the message says why: 1 means findings, and a pipeline
  # that cannot tell a broken bundle from a broken checker learns to ignore
  # both. Predates the readers; it went uncovered because a unit test walked
  # `Audit.call` and no user-shaped test walked the arm around it.
  def test_audit_that_cannot_run_exits_two_rather_than_one
    with_bundle do |b|
      dir = b.path
      board = File.join(dir, "board.md")
      File.delete(board)
      Dir.mkdir(board)
      run = run_cli([ "audit", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/could not run \(Errno::EISDIR/, run.err)
      assert_match(/This is exit 2, not 1/, run.err)
    end
  end

  # The same arm on the commit door's verb, and the one test in this suite that
  # stubs rather than building the world. It has to: `Records` already answers
  # a failed git, a missing git and an unparseable line as FINDINGS, so no
  # fixture reaches the rescue around it. The arm still has to exist and has to
  # be proven — the contract's floor is that a checker which crashed refuses,
  # and "unreachable today" is how a rescue rots into a `return 0`.
  def test_records_that_cannot_run_exits_two_rather_than_one
    with_bundle do |b|
      dir = b.path
      OKF::Pro::Records.stub(:staged_violations, ->(*) { raise IOError, "git went away" }) do
        run = run_cli([ "records", dir ])

        assert_equal OKF::Pro::BLOCK, run.status
        assert_match(/could not run \(IOError: git went away\)/, run.err)
        assert_match(/the staged diff was never read/, run.err)
      end
    end
  end

  def test_audit_needs_no_event
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_equal OKF::Pro::PASS, run_cli([ "audit", b.path ], stdin: "").status
    end
  end
  # ── the two argv verbs derivation added ───────────────────────────────────

  def test_snapshot_prints_the_mechanical_line_and_writes_nothing
    with_bundle do |b|
      b.in_flight("one").inbox("a capture")
      dir = b.path
      log_before = OKF::Pro.read_text(File.join(dir, "log.md"))
      run = run_cli([ "snapshot", dir ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/\A\* \*\*Snapshot\*\*: inbox 1/, run.out)
      assert_equal log_before, OKF::Pro.read_text(File.join(dir, "log.md"))
    end
  end

  # The rendered line travels WITH the counters rather than instead of them: it
  # is what a person appends to `log.md`, and a consumer that had to re-render
  # it from twelve numbers would be a second implementation of the one shape
  # the stop gate verifies.
  # `BundleRoot.resolve` accepts an index beside `log.md` alone, so a bundle can
  # resolve with no board to count.
  def test_snapshot_says_so_when_there_is_no_board_to_count
    with_bundle do |b|
      dir = b.path
      File.delete(File.join(dir, "board.md"))
      run = run_cli([ "snapshot", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/has no board\.md to count/, run.err)
    end
  end

  def test_snapshot_json_carries_the_line_and_all_twelve_counters
    with_bundle do |b|
      b.in_flight("one").inbox("a capture")
      run = run_cli([ "snapshot", b.path, "--json" ])

      assert_equal OKF::Pro::PASS, run.status
      payload = JSON.parse(run.out)

      assert_equal OKF::Pro::Snapshot::PATTERNS.keys.sort, payload["counters"].keys.sort
      assert_equal 1, payload["counters"]["in flight"]
      assert_equal run_cli([ "snapshot", b.path ]).out.chomp, payload["line"]
    end
  end

  def test_snapshot_pretty_is_json_indented
    with_bundle do |b|
      run = run_cli([ "snapshot", b.path, "--pretty" ])

      assert_match(/\A\{\n  "line"/, run.out)
    end
  end

  def test_snapshot_refuses_an_unknown_flag_rather_than_reading_it_as_a_directory
    with_bundle do |b|
      run = run_cli([ "snapshot", b.path, "--full" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/invalid option: --full/, run.err)
    end
  end

  def test_snapshot_fails_loud_outside_a_bundle
    Dir.mktmpdir do |dir|
      run = run_cli([ "snapshot", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  def test_unverified_reports_and_still_exits_zero
    with_bundle do |b|
      b.concept("reference/pricing.md", type: "Briefing",
        generated: { by: "claude", at: "2026-08-10" })
      run = run_cli([ "unverified", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/1 concept\(s\) awaiting the owner's read/, run.out)
      assert_match(/the state is the truth, not a defect/, run.out)
    end
  end

  def test_unverified_says_so_when_nothing_awaits
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      run = run_cli([ "unverified", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/nothing awaits a read/, run.out)
    end
  end

  # Structured rows rather than the rendered sentences, because a consumer that
  # had to take prose apart with a regex breaks on the next wording change —
  # and the wording is written for a person.
  def test_unverified_json_emits_structured_rows
    with_bundle do |b|
      b.concept("reference/pricing.md", type: "Briefing",
        generated: { by: "claude", at: "2026-08-10" })
      run = run_cli([ "unverified", b.path, "--json" ])

      assert_equal OKF::Pro::PASS, run.status
      rows = JSON.parse(run.out)

      assert_equal 1, rows.size
      assert_equal "reference/pricing", rows.first["id"]
      assert_equal "claude", rows.first["by"]
      assert_equal "unverified", rows.first["trust"]
    end
  end

  def test_unverified_json_of_a_clean_bundle_is_an_empty_list
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_equal [], JSON.parse(run_cli([ "unverified", b.path, "--json" ]).out)
    end
  end

  def test_unverified_fails_loud_outside_a_bundle
    Dir.mktmpdir do |dir|
      assert_equal OKF::Pro::BLOCK, run_cli([ "unverified", dir ]).status
    end
  end

  # The hook protocol reads every exit but 2 as NON-BLOCKING, so a check that
  # crashes with an unrescued exception is an edit waved through over a gate
  # lying on the floor. Any crash refuses. The trigger here is real: board.md
  # replaced by a directory makes the read raise EISDIR.
  def test_a_crashed_check_refuses_instead_of_failing_open
    with_bundle(nested: true) do |b|
      b.path
      board = File.join(b.dir, "board.md")
      File.delete(board)
      Dir.mkdir(board)

      run = run_cli(%w[cap-check],
        stdin: bundle_event(b.path, ".okf/board.md", tool_name: "Edit"))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/ENFORCEMENT ERROR/, run.err)
      assert_match(/refused/, run.err)
    end
  end

  # The block's whole justification is token economy, so it may not restate
  # what the lines around it already said. In-flight, inbox and the snapshot
  # were each printed twice, at the top of every session, by two renderings of
  # the same numbers — and a reader then has to work out which one is live.
  def test_the_banner_renders_each_counter_once
    with_bundle do |b|
      b.in_flight("one").inbox("a capture").snapshot_on("2026-08-12")
      lines = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path)).out.lines.map(&:chomp)

      refute(lines.any? { |l| l.start_with?("Board now —") }, "the board counters are rendered twice")
      refute(lines.any? { |l| l =~ /\AAs of .*not live —/ }, "the snapshot is rendered twice")
      assert_equal 1, lines.count { |l| l.start_with?("Bundle state at session start —") }
      assert_equal 1, lines.count { |l| l.start_with?("Last snapshot") }
    end
  end

  # The one that survives the merge: the logged line carries all twelve
  # counters, which is what "read the delta" is read against, and the two the
  # banner cannot recompute cheaply are among them. Labelling it by its day is
  # what stops a reader taking it for today's.
  def test_the_banner_carries_the_whole_logged_snapshot_labelled_by_its_day
    with_bundle do |b|
      b.in_flight("one").snapshot_on("2026-08-12")
      out = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path)).out

      assert_match(/^Last snapshot \(2026-08-12, not live\): \* \*\*Snapshot\*\*: /, out)
      assert_match(/unverified briefings 0/, out)
    end
  end

  # A shell redirect is a bypass, not a missing verb: `covered_by` answers
  # "Edit or Write" for it, because the trust guards read a tool event and a
  # redirect produces none. Counting it here told the adopter a verb could
  # have done something no verb covers — and kept telling them every session,
  # for a guard that fired and an owner who denied, which is the system
  # working.
  def test_the_banner_counts_only_what_a_verb_could_have_done
    with_bundle do |b|
      OKF::Pro::Friction.record(b.bundle_path, "shell", "board.md", "cat > .okf/board.md")
      out = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path)).out

      refute_match(/done by hand/, out)
    end
  end

  def test_the_banner_counts_the_edits_a_verb_covers_beside_the_ones_it_does_not
    with_bundle do |b|
      OKF::Pro::Friction.record(b.bundle_path, "edit", "board.md")
      OKF::Pro::Friction.record(b.bundle_path, "shell", "board.md", "cat > .okf/board.md")
      out = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path)).out

      assert_match(/1 bundle edit\(s\) so far were done by hand/, out)
    end
  end

  # A log nobody could parse is a short count, not a quiet one, and the banner
  # is where a zero and an unknown must never be confused. It reported the
  # unwritable case and stayed silent on the unreadable one.
  def test_the_banner_says_so_when_the_log_could_not_be_read
    with_bundle do |b|
      log = OKF::Pro::Friction.log_path(b.bundle_path)
      FileUtils.mkdir_p(File.dirname(log))
      File.write(log, "not json\n{\"half\":\n")
      out = run_cli(%w[session-context], stdin: JSON.generate("cwd" => b.path)).out

      assert_match(/2 recorded line\(s\)/, out)
    end
  end

  # ── the flags the CI verbs never declared ─────────────────────────────────

  # 1 means "the bundle is broken" and 2 means "the checker could not run",
  # and a CI step with a typo'd flag must not report the first. `audit` and
  # `records` parsed no flags at all, so an undeclared one reached
  # `BundleRoot.resolve` as a directory and came back as a *finding*.
  def test_audit_reads_an_undeclared_flag_as_a_usage_error_not_a_finding
    run = run_cli(%w[audit --json])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/--json/, run.findings)
    refute_match(/holds no OKF bundle/, run.findings)
  end

  def test_records_reads_an_undeclared_flag_as_a_usage_error_not_a_finding
    run = run_cli(%w[records --json])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/--json/, run.findings)
    refute_match(/holds no OKF bundle/, run.findings)
  end

  # `--help` AFTER the directory reaches the verb's own parser; `okf pro <verb>
  # --help` is answered one layer up, in `run`, so this is the arm the
  # dispatcher never sees and the one the two CI verbs had no parser for.
  def test_every_reader_answers_help_from_its_own_parser
    OKF::Pro::CLI::READERS.each do |verb|
      run = run_cli([ verb, ".", "--help" ])

      assert_equal OKF::Pro::PASS, run.status, "#{verb} did not answer --help"
      assert_match(/\AUsage: okf pro <command>/, run.out)
    end
  end

  # The declared-flags table is the mechanism, so the pin is on its promise
  # rather than on the two verbs that happened to break it — a reader added
  # later without an entry fails here rather than in someone's pipeline.
  def test_every_reader_refuses_an_undeclared_flag
    OKF::Pro::CLI::READERS.each do |verb|
      run = run_cli([ verb, "--not-a-flag" ])

      assert_equal OKF::Pro::BLOCK, run.status, "#{verb} did not refuse --not-a-flag"
    end
  end

  # ── the real process under a bare locale ──────────────────────────────────

  # In-process tests hand Event a String; the real bypass was the stream.
  # With LANG/LC_ALL unset (common in CI and git hooks) stdin arrives tagged
  # US-ASCII, and an em dash in an edit's new_string crashed the reader above
  # the dispatch rescue — ruby exited 1, which PreToolUse reads as
  # NON-BLOCKING, so the write the guard exists to stop proceeded.
  # With LANG unset — the common case in CI and in a git hook —
  # Encoding.default_external is US-ASCII, and a clean em dash in an edit's
  # new_string raised ArgumentError out of the first regex. That exits 1, which
  # the hook protocol reads as non-blocking: the guard bypassed by a punctuation
  # mark. Driven through the real entry point, in a real subprocess, because the
  # locale is a property of the process and not of a method call.
  def test_a_non_ascii_event_under_a_bare_locale_does_not_crash_the_gate
    okf_root = Gem.loaded_specs.key?("okf") ? Gem.loaded_specs["okf"].full_gem_path : File.expand_path("../../../okf", __dir__)
    Dir.mktmpdir do |dir|
      ev = JSON.generate("tool_name" => "Edit", "cwd" => dir,
        "tool_input" => { "file_path" => File.join(dir, "x.md"),
                          "new_string" => "verified \u2014 by hand" })
      env = { "LANG" => nil, "LC_ALL" => nil, "LC_CTYPE" => nil }
      argv = [ RbConfig.ruby, "-I#{okf_root}/lib", "-I#{File.expand_path("../../lib", __dir__)}",
               File.join(okf_root, "exe", "okf"), "pro", "hook", "guard-verified" ]
      IO.popen(env, argv, "r+", err: File::NULL) do |io|
        io.write(ev)
        io.close_write
        io.read
      end

      assert_equal 0, $?.exitstatus, "a crash here exits 1 — non-blocking, the guard bypassed"
    end
  end

  # ── every name in the table, through the table ────────────────────────────
  #
  # These four checks were reached only module-first — 34 direct calls to
  # Guards.journal_guard, ShellGuard.check, Reconcile.search and
  # Closing.stop_gate, and not one of them through CHECKS. The implementations
  # were covered; the binding from name to behaviour was not, so renaming a
  # key, or pointing one at the wrong module, was caught by nothing. It fails
  # closed — ENFORCEMENT MISCONFIGURED on every edit — which is not a bypass
  # but is still an outage nobody would see coming.

  def test_journal_guard_dispatches_to_the_journal_rule
    with_bundle do |b|
      b.write("journal/2020-01-01.md", "# 2020-01-01\n\nA day already recorded.\n")
      run = run_cli(%w[journal-guard],
        stdin: bundle_event(b.path, "journal/2020-01-01.md", tool_name: "Edit"))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/journal\/2020-01-01\.md is a past day/, run.err)
      assert_match(/append-only/, run.err)
    end
  end

  def test_shell_guard_dispatches_and_routes_its_ask_to_the_owner
    with_bundle(nested: true) do |b|
      run = run_cli(%w[shell-guard],
        stdin: JSON.generate("tool_name" => "Bash", "cwd" => b.path,
          "tool_input" => { "command" => "cat > .okf/reference/x.md <<'EOF'\nverified: me\nEOF" }))

      assert_equal OKF::Pro::PASS, run.status
      decision = JSON.parse(run.out).fetch("hookSpecificOutput")
      assert_equal "ask", decision.fetch("permissionDecision")
      assert_match(/bypass the trust guards/, decision.fetch("permissionDecisionReason"))
    end
  end

  def test_reconcile_search_dispatches_to_law_one
    with_bundle do |b|
      b.concept("glossary/binding-estimate.md", type: "Term",
        body: "# Definition\n\nA binding estimate fixes the price for the listed inventory.\n")
      run = run_cli(%w[reconcile-search],
        stdin: bundle_event(b.path, "reference/binding-estimate-notes.md", tool_name: "Write"))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/RULE 1 — reconciliation/, run.err)
      assert_match(%r{glossary/binding-estimate}, run.err)
    end
  end

  # No `today:` to pass through the table, so this leans on the one refusal
  # that holds on every calendar day: work happened and no snapshot closes it.
  def test_stop_gate_dispatches_to_rule_two
    with_bundle(git: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
      b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")
      run = run_cli(%w[stop-gate], stdin: JSON.generate("cwd" => b.path))

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/RULE 2/, run.err)
    end
  end

  # The table is the only place a name is bound to behaviour, so a name the
  # settings file invokes and the table does not know is enforcement that
  # cannot run. settings_test proves the hook commands execute; it proves that
  # against a stub, which cannot tell a real check name from a typo.
  def test_every_check_the_settings_file_invokes_is_a_name_the_cli_knows
    settings = File.expand_path("../../lib/okf/pro/template/seed/.claude/settings.json", __dir__)
    invoked = JSON.parse(OKF::Pro.read_text(settings)).fetch("hooks").values.flatten
                  .flat_map { |m| m.fetch("hooks", []) }
                  .map { |h| h["command"].to_s.split.last }.compact
                  .uniq

    refute_empty invoked
    invoked.each do |name|
      assert_includes OKF::Pro::CLI::NAMES, name,
        "settings.json invokes '#{name}', which CLI dispatch does not know"
    end
  end
end
