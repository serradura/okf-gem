# frozen_string_literal: true

require "test_helper"

# These run the real analyzers against a real bundle. A mock here would be
# testing the mock: the whole value of the check is that it agrees with what
# `okf validate` and `okf lint` would say.
class ConformanceTest < OKF::Pro::TestCase
  def test_a_clean_bundle_passes
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      target = OKF::Pro::Target.for(edit_event(b.path, "glossary/term.md"))

      assert_empty OKF::Pro::Conformance.check(target)
    end
  end

  def test_refuses_a_file_with_no_frontmatter
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.raw("glossary/broken.md", "# Broken\n\nNo frontmatter, so no type.\n")
      target = OKF::Pro::Target.for(edit_event(b.path, "glossary/broken.md"))

      refusal = OKF::Pro::Conformance.check(target)

      assert_equal 1, refusal.size
      assert_match(/okf validate failed/, refusal.first)
      assert_match(/glossary\/broken\.md/, refusal.first)
    end
  end

  def test_refuses_an_empty_type
    with_bundle do |b|
      b.raw("glossary/typeless.md", "---\ntype:\ntitle: Typeless\n---\n\n# Typeless\n\nBody.\n")
      target = OKF::Pro::Target.for(edit_event(b.path, "glossary/typeless.md"))

      assert_match(/okf validate failed/, OKF::Pro::Conformance.check(target).first)
    end
  end

  # Lint is advisory at the CLI unless you pass --fail-on warn. Here a warning
  # is a refusal, which is the same decision made once instead of per-caller.
  def test_refuses_a_lint_warning
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path # finishes first; the index below has to survive the build
      b.write("glossary/index.md",
        "# Glossary\n\n* [term](term.md) - fixture.\n* [ghost](ghost.md) - not there.\n")
      target = OKF::Pro::Target.for(edit_event(dir, "glossary/index.md"))

      refusal = OKF::Pro::Conformance.check(target)

      assert_equal 1, refusal.size
      assert_match(/okf lint flagged/, refusal.first)
    end
  end

  def test_a_nil_target_has_no_opinion
    assert_empty OKF::Pro::Conformance.check(nil)
  end

  # Lint is bundle-WIDE while this gate fires on ONE edit. Everything is
  # still reported — dropping the other files' warnings would hide the edit
  # that breaks a neighbour — but only the edited file's warnings are called
  # yours. A pre-existing warning elsewhere used to arrive under the heading
  # "your edit" on every edit in the bundle, and a gate that blames you for
  # what you did not do is a gate people switch off.
  def test_a_pre_existing_warning_elsewhere_is_not_called_your_edit
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.concept("reference/other.md", type: "Briefing")
      dir = b.path
      File.write(File.join(dir, "reference", "index.md"),
        "# Reference\n\n* [other](other.md) - x.\n* [ghost](ghost.md) - missing.\n")

      msgs = OKF::Pro::Conformance.check(
        OKF::Pro::Target.for(edit_event(dir, "glossary/term.md"))
      )

      refute_empty msgs
      refute_match(/flagged your edit/, msgs.first)
      assert_match(/elsewhere in the bundle/, msgs.first)
      assert_match(/ghost/, msgs.first)
    end
  end

  def test_a_warning_on_the_edited_file_is_called_yours
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      File.write(File.join(dir, "glossary", "index.md"),
        "# Glossary\n\n* [term](term.md) - x.\n* [ghost](ghost.md) - missing.\n")

      msgs = OKF::Pro::Conformance.check(
        OKF::Pro::Target.for(edit_event(dir, "glossary/index.md"))
      )

      assert_match(/flagged your edit/, msgs.first)
    end
  end

  # ── what the gate used to drop on the floor ───────────────────────────────

  # §9 forbids the validator from REJECTING a soft problem, so the trust
  # family's grammar failures arrive as warnings — and this gate read
  # `result.errors` only. The class it hides is the worst one available: a
  # scalar `verified:` fires the attestation guard (the word is there), the
  # owner is asked and approves, and then the reader drops the malformed value.
  # The tier stays unverified, the To-read line is demanded forever, and every
  # door agrees the bundle is fine.
  def test_a_malformed_verified_block_is_reported_rather_than_discarded
    with_bundle do |b|
      b.raw("reference/x.md", <<~MD)
        ---
        type: Briefing
        title: X
        description: A briefing whose attestation is written as a scalar.
        generated: { by: claude/opus-5, at: 2026-08-10 }
        verified: human:rod
        ---

        # X

        Body long enough to clear the stub threshold, with a link to [the board](/board.md).
      MD
      target = OKF::Pro::Target.for(edit_event(b.path, "reference/x.md"))

      messages = OKF::Pro::Conformance.check(target)

      refute_empty messages, "the validator warned and the gate said nothing"
      assert_match(/verified should be a mapping or a list of mappings/, messages.join("\n"))
    end
  end

  # A clean bundle must stay silent, or the gate is noise. This is the pin that
  # stops the fix above from being applied to every edit in every bundle.
  def test_the_validators_warnings_do_not_speak_when_there_are_none
    with_bundle do |b|
      b.concept("reference/x.md", type: "Briefing",
        generated: { by: "claude/opus-5", at: "2026-08-10" },
        verified: [ { by: "human:rod", at: "2026-08-11" } ])
      target = OKF::Pro::Target.for(edit_event(b.path, "reference/x.md"))

      assert_empty OKF::Pro::Conformance.check(target)
    end
  end

  # The contract's third clause, asked of the gate's own path. Measured before
  # the fix: `skipped_checks: [:expired, :stale]` with `healthy?: true` — seven
  # of the nine blocking checks ran and the gate called it clean. Nothing must
  # be SILENTLY skipped: `expired` runs because the clock is supplied, `stale`
  # is excluded in source, and this asserts the residue is empty rather than
  # trusting that it is.
  def test_the_gate_leaves_no_check_silently_unrun
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      report = OKF::Bundle::Linter.call(OKF::Bundle::Reader.read(b.bundle_path),
        today: Date.today, except: [ :stale ])

      assert_empty Array(report.stats[:skipped_checks]),
        "the gate reports clean over these — pass what they need, or exclude them in source"
    end
  end

  # And the guard on the guard: if okf ever grows a clock-gated check this gate
  # does not know how to supply, the confession fires rather than the gate
  # quietly not running it.
  def test_a_check_that_could_not_run_is_confessed
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      report = OKF::Bundle::Linter.call(OKF::Bundle::Reader.read(b.bundle_path))

      assert_equal %i[expired stale], Array(report.stats[:skipped_checks])
      assert_match(/unchecked rather than clean/, OKF::Pro::Conformance.confession(report).first)
    end
  end
end
