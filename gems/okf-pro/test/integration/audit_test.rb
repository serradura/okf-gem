# frozen_string_literal: true

require "test_helper"

# The CI door. Same invariants as the hooks, minus the ones that need a tool
# event — and with the snapshot question asked about the log's newest day
# rather than today, because a push can land on a day nobody worked.
class AuditTest < OKF::Pro::TestCase
  def test_a_healthy_bundle_is_clean
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")

      assert_empty OKF::Pro::Audit.call(b.path)
    end
  end

  # The hook door surfaces the validator's WARNINGS as well as its errors, and
  # this door dropped them: `conformance` returned early on `valid?`. So a
  # malformed trust block was caught at the agent's tool boundary and waved
  # through by CI and by the pre-commit door — the one path an edit made in an
  # editor actually takes.
  def test_reports_a_validator_warning_and_not_only_an_error
    with_bundle do |b|
      b.raw("reference/a-briefing.md",
        "---\ntype: Reference\ntitle: A briefing\ndescription: A briefing carrying a scalar verified.\n" \
        "verified: human:rod\n---\n\n# A briefing\n\nA body long enough to clear the stub threshold.\n")
      msgs = OKF::Pro::Audit.call(b.path)

      assert(msgs.any? { |m| m.include?("verified should be a mapping") },
        "the validator's warning never reached the CI door: #{msgs.inspect}")
    end
  end

  # The contract's third clause, asked of the CI door this time. `Conformance`
  # supplies the clock and excludes `stale` in source; this door called
  # `Linter.call(bundle)` bare, so `expired` and `stale` were skipped and it
  # still printed "clean". Two doors, one clause, and only one of them kept it.
  def test_the_ci_door_leaves_no_check_silently_unrun
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_empty Array(OKF::Pro::Audit.linted(::OKF::Bundle::Reader.read(b.bundle_path)).stats[:skipped_checks]),
        "the CI door reports clean over these — pass what they need, or exclude them in source"
    end
  end

  def test_reports_a_conformance_error
    with_bundle do |b|
      b.raw("glossary/broken.md", "# Broken\n\nNo frontmatter.\n")
      b.snapshot_on("2026-08-12")

      findings = OKF::Pro::Audit.call(b.path)

      assert_equal 1, findings.size
      assert_match(/validate/, findings.first)
    end
  end

  def test_reports_a_lint_warning
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")
      dir = b.path
      File.write(File.join(dir, "glossary", "index.md"),
        "# Glossary\n\n* [term](term.md) - x.\n* [ghost](ghost.md) - missing.\n")

      msgs = OKF::Pro::Audit.call(dir)

      # Both channels report this one, and the overlap is deliberate. `validate`
      # and `lint` stay separate (constraint 4) and each owns its own side of
      # the same broken link, under its own check name — `broken_link` is §6.1
      # tolerating it, `broken_index_entry` is curation refusing to. Collapsing
      # them here would mean choosing which door to go deaf in, and the
      # validator's channel is the one that carries a malformed trust block.
      assert(msgs.any? { |m| m.start_with?("  lint") }, msgs.inspect)
      assert(msgs.any? { |m| m.start_with?("  validate") }, msgs.inspect)
    end
  end

  def test_reports_a_missing_snapshot_on_the_newest_day
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.log_day("2026-08-12", "* **Creation**: something.")
      b.log_day("2026-08-11", "* **Snapshot**: inbox 0 · in flight 0/5")

      findings = OKF::Pro::Audit.call(b.path)

      assert_equal 1, findings.size
      assert_match(/newest day \(2026-08-12\) carries no Snapshot/, findings.first)
    end
  end

  # The distinction from stop-gate. A push on a quiet Sunday must not fail
  # because the newest entry is Friday's.
  def test_an_older_newest_day_is_fine_if_it_carries_its_snapshot
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.log_day("2026-08-11", "* **Snapshot**: inbox 0 · in flight 0/5")

      assert_empty OKF::Pro::Audit.call(b.path)
    end
  end

  def test_reports_pairing_failures
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.write("projects/orphan/index.md", "# Orphan\n\nOngoing.\n")
      b.snapshot_on("2026-08-12")

      assert_match(%r{pairing.*projects/orphan}, OKF::Pro::Audit.call(b.path).first)
    end
  end

  def test_refuses_a_directory_that_holds_no_bundle
    Dir.mktmpdir do |dir|
      findings = OKF::Pro::Audit.call(dir)

      assert_equal 1, findings.size
      assert_match(/holds no OKF bundle/, findings.first)
    end
  end

  def test_an_empty_log_is_not_a_finding
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_empty OKF::Pro::Audit.call(b.path)
    end
  end
  # ── the log's shape at this door ──────────────────────────────────────────

  # Nothing enforces the file's newest-first convention, and taking the first
  # heading made the audit interrogate the oldest day — which had its
  # snapshot — while the real newest day had none. The fixture builder sorts
  # its days, so the out-of-order file is written by hand here.
  def test_the_newest_day_is_the_maximum_date_not_the_first_heading
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.write(File.join(dir, "log.md"), <<~MD)
        # Update Log

        ## 2026-08-11
        * **Snapshot**: inbox 0 · in flight 0/5

        ## 2026-08-12
        * **Creation**: appended at the bottom, against convention.
      MD

      findings = OKF::Pro::Audit.call(dir)

      assert_equal 1, findings.size
      assert_match(/newest day \(2026-08-12\) carries no Snapshot/, findings.first)
    end
  end

  def test_a_prose_mention_of_the_word_snapshot_does_not_satisfy_ci
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.log_day("2026-08-12", "- Rewrote the Snapshot checker end to end.")

      findings = OKF::Pro::Audit.call(b.path)

      assert_match(/carries no Snapshot line/, findings.first)
    end
  end

  # A heading no check will ever look under must not rot in silence: days()
  # skips what the calendar rejects, and the audit says so.
  def test_a_malformed_day_heading_is_a_finding
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.log_day("2026-08-32", "* **Snapshot**: inbox 0 · in flight 0/5")
      b.snapshot_on("2026-08-12")

      findings = OKF::Pro::Audit.call(b.path)

      assert(findings.any? { |f| f =~ /'## 2026-08-32' is not a calendar date/ }, findings.inspect)
    end
  end

  # ── the board's date grammar ──────────────────────────────────────────────

  # A dated line the counters cannot parse counted as zero, silently — the
  # editor-made commit this door exists for could land an undated deadline
  # that no counter would ever confess to missing.
  def test_reports_a_dated_line_the_counters_cannot_read
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.board_lines("Deadlines", "Due Aug 18 — filing")
      b.board_lines("Waiting", "Landlord: inspection — chase soon")
      b.inbox("heard something at lunch, undated")
      b.snapshot_on("2026-08-12")

      findings = OKF::Pro::Audit.call(b.path)

      assert(findings.any? { |f| f =~ /board.*7-day warning cannot see it/ }, findings.inspect)
      assert(findings.any? { |f| f =~ /board.*past-chase counter cannot see it/ }, findings.inspect)
      assert(findings.any? { |f| f =~ /board.*oldest-capture counter cannot see it/ }, findings.inspect)
    end
  end

  # ── two bundles, one directory ────────────────────────────────────────────

  # The doors disagree there by construction — the guards govern a file
  # outside .okf by the outer root (a root that does not contain the file
  # is no root of it) while this audit governs .okf. Neither choice is
  # wrong; the layout is, and a disagreement nobody is told about is the
  # silent failure the contract forbids.
  def test_a_directory_that_is_a_bundle_and_holds_one_is_a_finding
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")
      repo = b.path
      File.write(File.join(repo, "index.md"), "# Outer\n")
      File.write(File.join(repo, "board.md"), "# Board\n")

      findings = OKF::Pro::Audit.call(repo)

      assert(findings.any? { |f| f =~ /two roots, one directory/ }, findings.inspect)
      assert(findings.any? { |f| f =~ /the doors disagree/ }, findings.inspect)
    end
  end

  def test_an_ordinary_nested_bundle_is_not_flagged
    with_bundle(nested: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")

      refute(OKF::Pro::Audit.call(b.path).any? { |f| f.include?("two roots") })
    end
  end

  def test_a_flat_bundle_alone_is_not_flagged
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")

      refute(OKF::Pro::Audit.call(b.path).any? { |f| f.include?("two roots") })
    end
  end

  # ── the closed core ───────────────────────────────────────────────────────

  # The audit used to crash on a missing board (a backtrace is not a finding)
  # and stay silent on a missing log (which quietly disabled the snapshot
  # check). Both are structure findings now.
  def test_a_missing_board_is_a_finding_not_a_crash
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.delete(File.join(dir, "board.md"))

      findings = OKF::Pro::Audit.call(dir)

      assert(findings.any? { |f| f =~ /structure board\.md is missing/ })
    end
  end

  def test_a_missing_log_is_a_finding
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.delete(File.join(dir, "log.md"))

      assert(OKF::Pro::Audit.call(dir).any? { |f| f =~ /structure log\.md is missing/ })
    end
  end

  def test_a_missing_journal_is_a_finding
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      FileUtils.rm_rf(File.join(dir, "journal"))

      assert(OKF::Pro::Audit.call(dir).any? { |f| f =~ %r{structure journal/ is missing} })
    end
  end

  def test_a_missing_corpus_is_a_finding
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.delete(File.join(dir, "areas", "corpus.md"))
      File.write(File.join(dir, "areas", "index.md"), "# Areas\n")

      assert(OKF::Pro::Audit.call(dir).any? { |f| f =~ %r{structure areas/corpus\.md is missing} })
    end
  end

  # The one deletion the design allows. Fixtures never create roadmap.md, so
  # every clean audit above already proves it silently — this pins it on purpose.
  def test_a_missing_roadmap_is_not_a_finding
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.snapshot_on("2026-08-12")

      refute(OKF::Pro::Audit.call(b.path).any? { |f| f.include?("structure") })
    end
  end

  # Rule 3 at this door. An editor-made commit — the bypass the door exists
  # for — used to sail past with the board over its own cap.
  def test_audit_reports_a_board_over_cap
    with_bundle do |b|
      b.in_flight("one", "two", "three", "four", "five", "six")
      b.budget(cap: 5, declared: 6)

      findings = OKF::Pro::Audit.call(b.path)

      assert findings.any? { |f| f =~ /RULE 3.*6 in flight against a cap of 5/ }, findings.inspect
    end
  end

  def test_audit_reports_a_lying_budget_header
    with_bundle do |b|
      b.in_flight("the only one")
      b.budget(declared: 3)

      findings = OKF::Pro::Audit.call(b.path)

      assert findings.any? { |f| f =~ /Header claims 3.*section holds 1/ }, findings.inspect
    end
  end
end
