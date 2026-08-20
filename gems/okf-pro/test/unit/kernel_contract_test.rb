# frozen_string_literal: true

require "test_helper"

# What this gem takes from okf, pinned.
#
# The Gemfile develops against the kernel checkout next door, so every other
# test here runs against whatever `okf/lib/okf/version.rb` says today. That is
# the arrangement that lets a rename land silently: okf's renames do not raise,
# they return nil (`timestamp` → `generated_at`, `area` → `top_dir`), and a gate
# reading nil decides nothing and reports clean.
#
# THE PIN IS BEHAVIOURAL, not `respond_to?`. Every surface named here responds
# today; the failure class is a method that keeps its name and changes its
# meaning, which a shape check cannot see. So each assertion below drives real
# input through and asserts the answer.
class KernelContractTest < OKF::Pro::TestCase
  # ── §5.2 / §5.3: the trust vocabulary the whole read-owed rule is written in
  #
  # Four call sites depend on these three answers agreeing (see the comment over
  # Pairing#awaiting_read?). If `trust_tier` ever stops distinguishing a
  # `process:` actor from a `human:` one, a briefing nobody read loses its
  # To-read line and leaves the attention system in silence.
  def test_the_trust_family_answers_what_the_read_owed_rule_asks
    with_bundle do |b|
      b.concept("reference/machine.md", type: "Briefing",
        generated: { by: "claude/opus-5", at: "2026-08-10T09:00:00Z" },
        verified: { by: "process:nightly", at: "2026-08-11T02:00:00Z" })
      b.concept("reference/read.md", type: "Briefing",
        generated: { by: "claude/opus-5", at: "2026-08-10T09:00:00Z" },
        verified: [ { by: "human:rod", at: "2026-08-11T18:00:00Z" } ])
      b.concept("glossary/hand.md", type: "Term")
      concepts = OKF::Bundle::Reader.read(b.bundle_path).concepts.each_with_object({}) { |c, h| h[c.id] = c }

      machine = concepts.fetch("reference/machine")
      assert machine.declared_generated?
      assert_equal :machine_confirmed, machine.trust_tier
      assert_equal "machine-confirmed", machine.trust
      assert_equal "claude/opus-5", machine.generated_by
      assert_equal "2026-08-10T09:00:00Z", machine.generated_at

      assert_equal :human_reviewed, concepts.fetch("reference/read").trust_tier

      hand = concepts.fetch("glossary/hand")
      refute hand.declared_generated?, "a hand-written concept declares no provenance and owes no read"
      assert_equal :unverified, hand.trust_tier
    end
  end

  # §5.3 again, from the direction that bit: a bare mapping is a one-element
  # list, and a SCALAR is neither. The scalar case is the dangerous one — the
  # attestation guard fires on the word, the owner approves, and the reader
  # drops the value — so what is pinned is that it still reads as unverified
  # and that the validator still says why.
  def test_a_scalar_verified_reads_as_unverified_and_the_validator_says_so
    with_bundle do |b|
      b.raw("reference/x.md", <<~MD)
        ---
        type: Briefing
        title: X
        description: Attestation written as a scalar.
        generated: { by: claude/opus-5, at: 2026-08-10 }
        verified: human:rod
        ---

        # X

        Body long enough to clear the stub threshold, linking [the board](/board.md).
      MD
      bundle = OKF::Bundle::Reader.read(b.bundle_path)
      concept = bundle.concepts.find { |c| c.id == "reference/x" }

      assert_equal :unverified, concept.trust_tier
      result = OKF::Bundle::Validator.call(bundle)
      assert result.valid?, "§9 forbids the validator rejecting a soft problem — it must stay a warning"
      assert_match(/verified should be a mapping or a list of mappings/,
        result.warnings.map { |w| w[:message] }.join(" "))
    end
  end

  # §5.4, which Reconcile now reads. Absent `status` means `stable`, and that
  # default is what keeps the deprecated annotation from firing on every hit in
  # a bundle that has never written the field.
  def test_status_defaults_to_stable_and_deprecated_survives_the_read
    with_bundle do |b|
      b.concept("glossary/old.md", type: "Term", status: "deprecated")
      b.concept("glossary/new.md", type: "Term")
      concepts = OKF::Bundle::Reader.read(b.bundle_path).concepts.each_with_object({}) { |c, h| h[c.id] = c }

      assert_equal "deprecated", concepts.fetch("glossary/old").status
      assert_equal "stable", concepts.fetch("glossary/new").status
    end
  end

  # ── the linter's severity map, frozen
  #
  # `Conformance.check` blocks on `report.warnings` and reports `report.info`,
  # so this map IS what the gate refuses on — okf's classification, adopted
  # wholesale. A check moved between severities changes what an edit is stopped
  # for, in a gem whose dependency floor lets okf move underneath it.
  #
  # Snapshotted whole rather than spot-checked: a spot check on the nine warns
  # would miss a tenth arriving, which is the change that makes the gate refuse
  # something it never refused before.
  SEVERITIES = {
    orphan: :warn,
    not_in_index: :warn,
    disconnected_component: :info,
    unlinked: :info,
    missing_concept: :info,
    broken_index_entry: :warn,
    stub: :info,
    missing_title: :info,
    missing_description: :info,
    missing_generated: :info,
    expired: :info,
    stale: :warn,
    uncited_external: :info,
    broken_source: :warn,
    unattributed_claim: :warn,
    unused_source: :info,
    unprefixed_actor: :info,
    incomplete_computation: :warn,
    broken_attestation_ref: :warn,
    legacy_timestamp: :info,
    legacy_citations: :info,
    duplicate_title: :info,
    unused_reference_def: :info,
    undefined_reference: :warn,
    self_link: :info,
    log_order: :info
  }.freeze

  def test_the_severity_map_is_what_this_gate_was_built_against
    assert_equal SEVERITIES, OKF::Bundle::Linter::SEVERITIES,
      "okf's severity map moved. Read the diff before updating this snapshot: a check promoted to " \
      ":warn is a new reason every edit can be refused, and one demoted is a gate that quietly " \
      "stopped stopping things."
  end

  # The gate's blocking set, stated as a count so the snapshot above cannot be
  # updated thoughtlessly. Nine, and `okf pro hook check-okf` refuses on all
  # of them — including the partition it labels "elsewhere in the bundle".
  def test_nine_checks_block_an_edit
    warns = OKF::Bundle::Linter::SEVERITIES.select { |_, level| level == :warn }.keys

    assert_equal 9, warns.size, "the number of things an edit can be refused for changed"
    assert_equal %i[orphan not_in_index broken_index_entry stale broken_source unattributed_claim
                    incomplete_computation broken_attestation_ref undefined_reference].sort,
      warns.sort
  end

  # ── the shapes the checker's own logic is built on
  #
  # Each of these was a candidate for replacing okf-pro code with a kernel call,
  # and each was rejected on a measured difference. The rejections are only as
  # good as the measurements, so the measurements are asserted.
  def test_the_kernel_shapes_the_reuse_audit_turned_on
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      b.write("reference/attachment.pdf", "not markdown")
      b.raw("learnings/no-front.md", "# No frontmatter\n\nSo the reader cannot parse it.\n")
      bundle = OKF::Bundle::Reader.read(b.bundle_path)

      # #paths is markdown only, so it cannot stand in for the board's link
      # targets: a board line pointing at an attachment or a directory would
      # read as broken, and `broken_targets` feeds the stop gate — the agent
      # could not end a session on an ordinary board.
      assert bundle.paths.all? { |p| p.end_with?(".md") }
      refute_includes bundle.paths, "/reference/attachment.pdf"

      # #directories answers bare names with "." for the root, not the
      # bundle-absolute "/projects/" form the board writes.
      assert_includes bundle.directories, "glossary"
      refute_includes bundle.directories, "/glossary/"

      # A file with no frontmatter is not a concept; it lands in #unparseable.
      # The pairing checks iterate #concepts and therefore cannot see it, which
      # is why `Audit.conformance` asks the validator rather than trusting them.
      refute_includes bundle.concepts.map(&:id), "learnings/no-front"
      refute_empty bundle.unparseable

      # The dominant board spelling for a project is a trailing slash, and
      # Links.resolve_path answers nil to it. Substituting it for the board's
      # own target normalisation would drop every project link in silence.
      assert_nil OKF::Markdown::Links.resolve_path("/projects/home-move/",
        from: "board.md", bundle: b.bundle_path)
      assert_equal "projects/home-move/index.md",
        OKF::Markdown::Links.resolve_path("/projects/home-move/index.md",
          from: "board.md", bundle: b.bundle_path)
    end
  end
end
