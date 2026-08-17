# frozen_string_literal: true

require "test_helper"

# The guards scope through Target, so every event here is built against a real
# bundle in a nested fixture — cwd at the repository root, concepts under
# .okf/ — because the scoping IS part of what these tests pin.
class GuardsTest < OKF::Pro::TestCase
  # ── attestation ───────────────────────────────────────────────────────────

  # The guard asks; it does not deny. The owner reviews with the agent and the
  # agent holds the pen, so the write becomes an explicit owner approval — and
  # the approval is the attestation. What is pinned here: the trigger produces
  # an ask (a Hash), never a silent pass and never a flat refusal.
  def test_asks_on_verified_in_new_string
    with_bundle(nested: true) do |b|
      result = OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/glossary/x.md", new_string: "verified:\n  by: owner")
      )

      assert_kind_of Hash, result
      assert_match(/owner attestation/, result["ask"])
      assert_match(/approval is the attestation/, result["ask"])
      assert_match(/deny/, result["ask"])
    end
  end

  def test_asks_on_verified_in_new_str
    with_bundle(nested: true) do |b|
      refute_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/x.md", new_str: "verified: yes")
      )
    end
  end

  def test_asks_on_verified_in_write_content
    with_bundle(nested: true) do |b|
      refute_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/x.md", content: "---\ntype: Briefing\nverified: yes\n---\n")
      )
    end
  end

  def test_asks_on_verified_in_any_multiedit_edit
    with_bundle(nested: true) do |b|
      refute_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/x.md",
          edits: [ { new_string: "harmless" }, { new_string: "  verified: yes" } ])
      )
    end
  end

  def test_asks_on_indented_verified
    with_bundle(nested: true) do |b|
      refute_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/x.md", new_string: "    verified :  yes")
      )
    end
  end

  # The word appears constantly in this bundle's own prose. A guard that
  # refuses "unverified briefing" is a guard that gets switched off.
  def test_allows_the_word_in_prose
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/x.md",
          new_string: "The briefing is unverified, and that state is the truth.")
      )
    end
  end

  def test_allows_verified_mid_line
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/x.md", new_string: "a claim nobody verified: still open")
      )
    end
  end

  def test_ignores_non_markdown_files
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, ".okf/script.rb", new_string: "verified: yes")
      )
    end
  end

  def test_ignores_an_edit_that_adds_nothing
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.guard_verified(write_event(b.path, ".okf/x.md"))
    end
  end

  # `verified:` is bundle vocabulary. The repository's own README quotes the
  # frontmatter format as documentation, and the guard used to ask on it —
  # a false block, and in an unattended session (where "ask" fails closed) a
  # refusal of documentation. Outside the bundle, the guard has no business.
  def test_ignores_markdown_outside_the_bundle
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.guard_verified(
        write_event(b.path, "README.md", new_string: "verified: {by: me}   # the format, quoted")
      )
    end
  end

  # ── the append-only record ────────────────────────────────────────────────

  def test_refuses_editing_an_existing_past_day
    with_bundle(nested: true) do |b|
      b.write("journal/2020-01-01.md", "a record\n")
      refusal = OKF::Pro::Guards.journal_guard(
        edit_event(b.path, ".okf/journal/2020-01-01.md", new_string: "x"),
        today: Date.new(2026, 8, 12)
      )

      assert_equal 1, refusal.size
      assert_match(/append-only/, refusal.first)
      assert_match(%r{journal/2020-01-01\.md}, refusal.first)
    end
  end

  # Rule 2's fallback: a day too heavy to journal is reconstructed the next
  # morning, declared as reconstructed. That is a CREATE of a past day — and
  # it is the owner's call, so it asks rather than passing silently: bare
  # non-existence would let an agent fabricate any past date as quietly as
  # filing a note, and this same guard would then defend the forgery as
  # append-only history.
  def test_creating_a_missing_past_day_asks_the_owner
    with_bundle(nested: true) do |b|
      result = OKF::Pro::Guards.journal_guard(
        write_event(b.path, ".okf/journal/2026-08-11.md", content: "reconstructed\n"),
        today: Date.new(2026, 8, 12)
      )

      assert_kind_of Hash, result
      assert_match(/reconstruction/, result["ask"])
      assert_match(%r{journal/2026-08-11\.md}, result["ask"])
    end
  end

  def test_creating_a_distant_past_day_also_asks_never_passes
    with_bundle(nested: true) do |b|
      result = OKF::Pro::Guards.journal_guard(
        write_event(b.path, ".okf/journal/2020-01-01.md", content: "fabricated\n"),
        today: Date.new(2026, 8, 12)
      )

      assert_kind_of Hash, result
    end
  end

  def test_allows_today
    with_bundle(nested: true) do |b|
      b.write("journal/2026-08-12.md", "today\n")
      assert_empty OKF::Pro::Guards.journal_guard(
        edit_event(b.path, ".okf/journal/2026-08-12.md", new_string: "x"),
        today: Date.new(2026, 8, 12)
      )
    end
  end

  # A future-dated entry is a different mistake, and not this gate's. Refusing
  # it here would mean the guard has an opinion about planning.
  def test_allows_a_future_day
    with_bundle(nested: true) do |b|
      b.write("journal/2026-12-25.md", "planned\n")
      assert_empty OKF::Pro::Guards.journal_guard(
        edit_event(b.path, ".okf/journal/2026-12-25.md", new_string: "x"),
        today: Date.new(2026, 8, 12)
      )
    end
  end

  def test_ignores_files_outside_the_journal
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.journal_guard(
        edit_event(b.path, ".okf/learnings/2020-01-01.md", new_string: "x"),
        today: Date.new(2026, 8, 12)
      )
    end
  end

  def test_ignores_the_journal_index
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.journal_guard(
        edit_event(b.path, ".okf/journal/index.md", new_string: "x"),
        today: Date.new(2026, 8, 12)
      )
    end
  end

  # The calendar the guard protects is the bundle's. A dated file under
  # .tmp/ — where the rules send scratch work — or anywhere else outside the
  # bundle used to be blocked by the unanchored path match.
  def test_ignores_journal_shaped_paths_outside_the_bundle
    with_bundle(nested: true) do |b|
      assert_empty OKF::Pro::Guards.journal_guard(
        write_event(b.path, ".tmp/journal/2020-01-01.md", content: "scratch"),
        today: Date.new(2026, 8, 12)
      )
      assert_empty OKF::Pro::Guards.journal_guard(
        write_event(b.path, "journal/2020-01-01.md", content: "repo root, not bundle"),
        today: Date.new(2026, 8, 12)
      )
    end
  end
  # ── scoping is by the file's own bundle, never by cwd ─────────────────────

  # The first scoping fix keyed on BundleRoot.resolve(event.cwd), which never
  # walks up — so a session parked in any subdirectory was a session whose
  # trust gates found no bundle and silently disarmed. The file's ancestry
  # decides; cwd is only a fallback.
  def test_guards_hold_when_cwd_is_a_subdirectory
    with_bundle(nested: true) do |b|
      sub = File.join(b.path, "docs")
      Dir.mkdir(sub)
      forged = event(cwd: sub,
        tool_input: { file_path: File.join(b.path, ".okf/x.md"),
                      new_string: "verified: yes" })

      assert_kind_of Hash, OKF::Pro::Guards.guard_verified(forged)

      b.write("journal/2020-01-01.md", "a record\n")
      rewrite = event(cwd: sub,
        tool_input: { file_path: File.join(b.path, ".okf/journal/2020-01-01.md"),
                      new_string: "x" })

      refusal = OKF::Pro::Guards.journal_guard(rewrite, today: Date.new(2026, 8, 12))
      assert_equal 1, refusal.size
      assert_match(/append-only/, refusal.first)
    end
  end

  # The gate read a narrower grammar than the parser it defends: YAML
  # frontmatter may be a FLOW mapping, which the okf reader parses as a
  # real attestation and the line-anchored pattern never saw. Downstream
  # nothing recovered — unverified_ids and Attestation.report both skip
  # anything carrying verified — so the forgery was invisible to the
  # audit, to CI, and to the To-read pairing check.
  def test_a_flow_mapping_attestation_still_asks
    with_bundle do |b|
      dir = b.path
      content = "---\n{type: Briefing, title: X, generated: agent, verified: 2026-08-01}\n---\n\n# X\n"
      result = OKF::Pro::Guards.guard_verified(write_event(dir, "reference/x.md", content: content))

      assert_kind_of Hash, result
      assert_match(/owner attestation/, result["ask"])
    end
  end

  def test_a_quoted_flow_key_still_asks
    with_bundle do |b|
      content = %(---\n{type: Briefing, "verified": 2026-08-01}\n---\n)

      assert_kind_of Hash,
        OKF::Pro::Guards.guard_verified(write_event(b.path, "reference/x.md", content: content))
    end
  end

  # Both spellings the reader accepts, and nothing else: a sentence about
  # attestation is prose, and a guard that fires on prose is a guard people
  # switch off.
  def test_prose_about_verification_is_not_an_attestation
    with_bundle do |b|
      dir = b.path

      assert_empty OKF::Pro::Guards.guard_verified(
        write_event(dir, "reference/x.md", content: "The claim was verified by the vendor.\n")
      )
      assert_empty OKF::Pro::Guards.guard_verified(
        write_event(dir, "reference/x.md", content: "Ask whether it is verified: nobody had.\n")
      )
    end
  end

  def test_attests_knows_both_spellings
    assert OKF::Pro::Guards.attests?("verified: 2026-08-01")
    assert OKF::Pro::Guards.attests?("{type: X, verified: 2026-08-01}")
    refute OKF::Pro::Guards.attests?("a line that merely says verified twice, verified")
  end
end
