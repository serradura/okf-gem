# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::LinterTest < OKF::TestCase
  setup { @tmpdir = Dir.mktmpdir("okf-linter-test") }
  teardown { FileUtils.rm_rf(@tmpdir) }

  # ── Reachability ───────────────────────────────────────────────────────────

  test "orphan flags concepts with no inbound link and absent from every index" do
    write("hub.md", fm(title: "Hub") + "See [leaf](leaf.md).\n")
    write("leaf.md", fm(title: "Leaf") + "body\n")
    write("lonely.md", fm(title: "Lonely") + "body\n")

    # leaf is reachable (inbound from hub); hub and lonely are not.
    assert_equal %w[hub.md lonely.md], paths(:orphan)
  end

  test "orphan is silenced by an index.md listing" do
    write("index.md", "# Root\n\n* [A](a.md)\n")
    write("a.md", fm(title: "A") + "body\n")

    assert_empty checks(:orphan)
  end

  test "not_in_index flags a direct child of an indexed dir that the index omits" do
    write("index.md", "# Root\n\n* [Listed](listed.md)\n")
    write("listed.md", fm(title: "Listed") + "See [unlisted](unlisted.md).\n")
    write("unlisted.md", fm(title: "Unlisted") + "body\n")

    assert_equal %w[unlisted.md], paths(:not_in_index)
  end

  test "not_in_index ignores dirs without an index" do
    write("index.md", "# Root\n\n* [Sub](sub/)\n") # links the subdir, not a concept
    write("sub/a.md", fm(title: "A") + "body\n")   # sub/ has no index.md

    assert_empty checks(:not_in_index)
  end

  test "disconnected_component reports a multi-concept island, not singletons" do
    write("a.md", fm(title: "A") + "[b](b.md)\n")
    write("b.md", fm(title: "B") + "[a](a.md)\n")
    write("c.md", fm(title: "C") + "[d](d.md)\n")
    write("d.md", fm(title: "D") + "[c](c.md)\n")

    islands = checks(:disconnected_component)
    assert_equal 1, islands.size
    assert_equal 2, islands.first[:metric][:size]
  end

  test "unlinked flags a degree-0 concept even when an index lists it (unlike orphan)" do
    write("index.md", "# Root\n\n* [Loose](loose.md)\n")
    write("loose.md", fm(title: "Loose") + "no links, in or out\n")

    assert_empty checks(:orphan), "an index listing makes it reachable — not an orphan"
    assert_equal %w[loose.md], paths(:unlinked), "but listed ≠ linked — it still floats"
  end

  test "unlinked ignores a concept that has any cross-link, in or out" do
    write("a.md", fm(title: "A") + "[b](b.md)\n") # links out
    write("b.md", fm(title: "B") + "hi\n") # linked from a

    assert_empty checks(:unlinked)
  end

  # ── Backlog ─────────────────────────────────────────────────────────────────

  test "missing_concept is demand-ranked and counts raw references (no graph dedup)" do
    write("a.md", fm(title: "A") + "[z](/zebra.md) [z](/zebra.md) [a](/apple.md)\n")

    ranked = checks(:missing_concept)
    assert_equal %w[zebra.md apple.md], ranked.map { |f| f[:path] } # zebra (2) outranks apple (1)
    assert_equal 2, ranked.first[:metric][:references]
    assert_equal [ "a" ], ranked.first[:metric][:sources]
  end

  test "missing_concept ignores external links and links inside fences" do
    write("a.md", fm(title: "A") + "[ext](https://e.com/x.md)\n\n```\n[fenced](/ghost.md)\n```\n")

    assert_empty checks(:missing_concept)
  end

  test "broken_index_entry flags an index link to a missing concept" do
    write("index.md", "# Root\n\n* [Gone](gone.md)\n* [Here](here.md)\n")
    write("here.md", fm(title: "Here") + "body\n")

    entry = checks(:broken_index_entry).first
    assert_equal "index.md", entry[:path]
    assert_equal "gone.md", entry[:metric][:target]
  end

  # ── Completeness ────────────────────────────────────────────────────────────

  test "stub flags short bodies and honors min_body" do
    write("s.md", fm(title: "S") + "hi\n")
    write("big.md", fm(title: "Big") + ("x" * 100) + "\n")

    assert_equal %w[s.md], paths(:stub)
    assert_empty checks(:stub, min_body: 1)
  end

  test "missing_title, missing_description, and missing_generated fire per field" do
    write("notitle.md", fm(title: nil) + "a reasonably long body to avoid the stub check\n")
    write("nodesc.md", fm(title: "X", description: nil) + "a reasonably long body to avoid the stub check\n")

    assert_equal %w[notitle.md], paths(:missing_title)
    assert_equal %w[nodesc.md], paths(:missing_description)
    assert_equal %w[nodesc.md notitle.md], paths(:missing_generated) # neither records a change
  end

  test "missing_generated is quiet on either spelling — a legacy timestamp still counts" do
    write("legacy.md", fm(title: "L", timestamp: "2026-01-01") + "a body long enough to skip the stub check\n")
    write("modern.md", "---\ntype: Note\ntitle: M\ndescription: D\ngenerated:\n  by: human:x\n---\n\na body long enough to skip the stub check\n")

    assert_empty paths(:missing_generated)
  end

  # ── Freshness ───────────────────────────────────────────────────────────────

  test "stale uses the injected cutoff and never raises on a bad timestamp" do
    write("old.md", fm(title: "Old", timestamp: "2000-01-01") + "a body long enough to skip stub\n")
    write("new.md", fm(title: "New", timestamp: "2030-01-01") + "a body long enough to skip stub\n")
    write("bad.md", fm(title: "Bad", timestamp: "whenever") + "a body long enough to skip stub\n")

    cutoff = Time.iso8601("2015-01-01T00:00:00Z")
    assert_equal %w[old.md], paths(:stale, stale_before: cutoff)
    assert_empty checks(:stale) # disabled without a cutoff
  end

  # ── Provenance ──────────────────────────────────────────────────────────────

  test "uncited_external flags external claims without a Citations section" do
    write("uncited.md", fm(title: "U") + "backed by [src](https://e.com/x) and nothing more\n")
    write("cited.md", fm(title: "C") + "backed by [src](https://e.com/x)\n\n# Citations\n\n[1] [src](https://e.com/x)\n")

    assert_equal %w[uncited.md], paths(:uncited_external)
  end

  test "broken_source flags a bundle-relative source to a missing page, in either spelling" do
    write("c.md", fm(title: "C") + "a claim\n\n# Citations\n\n[1] [ref](/nope.md)\n")
    write("native.md",
      "---\ntype: Note\ntitle: N\nsources:\n  - resource: /gone.md\n  - resource: https://e.com/fine\n  - resource: all queries in project X\n---\n\nx\n")

    assert_equal %w[c.md native.md], paths(:broken_source).sort
  end

  # ── Hygiene ─────────────────────────────────────────────────────────────────

  test "duplicate_title groups concepts sharing a normalized title" do
    write("a.md", fm(title: "Shared") + "a body long enough to skip stub\n")
    write("b.md", fm(title: "shared") + "a body long enough to skip stub\n") # case-insensitive
    write("c.md", fm(title: "Unique") + "a body long enough to skip stub\n")

    dup = checks(:duplicate_title)
    assert_equal 1, dup.size
    assert_equal %w[a b], dup.first[:metric][:concepts]
  end

  test "reference definitions: unused is info, undefined is warn, fenced uses ignored" do
    write("a.md", fm(title: "A") + "a body long enough to skip stub\n")
    write("b.md", fm(title: "B") + "a body long enough to skip stub\n")
    write("r.md", fm(title: "R") +
      "A [use][u] and a [dangle][ghost].\n\n```\n[fenced][unused]\n```\n\n[u]: /a.md\n[unused]: /b.md\n")

    assert_equal [ "unused" ], checks(:unused_reference_def).map { |f| f[:metric][:label] }
    assert_equal [ "ghost" ], checks(:undefined_reference).map { |f| f[:metric][:label] }
  end

  test "self_link flags a concept that links to itself" do
    write("me.md", fm(title: "Me") + "See [me](me.md) for more of the same, at length here.\n")

    assert_equal %w[me.md], paths(:self_link)
  end

  # ── Selection, health, stats, shape ─────────────────────────────────────────

  test "only and except select which checks run" do
    write("lonely.md", fm(title: "L") + "hi\n") # orphan + stub + missing_timestamp

    assert_equal [ :orphan ], report(only: [ :orphan ]).findings.map { |f| f[:check] }.uniq
    refute_includes report(except: [ :stub ]).findings.map { |f| f[:check] }, :stub
  end

  test "a well-curated bundle is healthy" do
    write("index.md", "# Root\n\n* [A](a.md)\n* [B](b.md)\n")
    write("a.md", fm(title: "A", timestamp: "2026-01-01") + ("links to [b](b.md) " * 5) + "\n")
    write("b.md", fm(title: "B", timestamp: "2026-01-01") + ("points to [a](a.md) " * 5) + "\n")

    assert report.healthy?, report.warnings.inspect
  end

  test "stats summarize the bundle" do
    write("index.md", "# Root\n\n* [A](a.md)\n")
    write("a.md", fm(title: "A") + "[b](b.md)\n")
    write("b.md", fm(title: "B", type: "Metric") + "body\n")

    stats = report.stats
    assert_equal 2, stats[:concepts]
    assert_equal 1, stats[:edges]
    assert_equal({ "Note" => 1, "Metric" => 1 }, stats[:types])
    assert_equal [ { id: "b", in_degree: 1 } ], stats[:hubs]
  end

  test "findings are well-formed and the report is JSON-able" do
    write("lonely.md", fm(title: "L") + "hi\n")
    result = report

    result.findings.each do |finding|
      assert_includes %i[warn info], finding[:severity]
      %i[check path message metric].each { |key| assert finding.key?(key), "finding missing #{key}" }
    end
    assert_nothing_raised { JSON.generate(result.to_h) }
  end

  # ── the severity map and check registry are API (WI-3) ──────────────────────

  test "the severity map is a pinned constant — ids and levels, so neither drifts" do
    expected = {
      orphan: :warn, not_in_index: :warn, disconnected_component: :info, unlinked: :info,
      missing_concept: :info, broken_index_entry: :warn,
      stub: :info, missing_title: :info, missing_description: :info, missing_generated: :info,
      expired: :info, stale: :warn,
      uncited_external: :info, broken_source: :warn, unattributed_claim: :warn,
      unused_source: :info, unprefixed_actor: :info,
      incomplete_computation: :warn, broken_attestation_ref: :warn,
      legacy_timestamp: :info, legacy_citations: :info,
      duplicate_title: :info, unused_reference_def: :info, undefined_reference: :warn, self_link: :info,
      log_order: :info
    }

    assert_equal expected, OKF::Bundle::Linter::SEVERITIES
    # CHECKS is derived (SEVERITIES.keys), so pinning the map pins the registry
    # and its display order in the same stroke — no sync assertion needed.
    assert_equal expected.keys, OKF::Bundle::Linter::CHECKS
  end

  test "the retired ids are gone from every registry that could silently keep them" do
    require "okf/cli" # lazy by design; this test reads the display categories
    %i[missing_timestamp broken_citation].each do |old|
      refute_includes OKF::Bundle::Linter::CHECKS, old
      refute_includes OKF::Concept::CONCEPT_SCOPED_CHECKS, old
      refute_includes OKF::CLI::Lint::LINT_CATEGORIES.values.flatten, old
    end
    assert_equal OKF::Bundle::Linter::CHECKS.sort, OKF::CLI::Lint::LINT_CATEGORIES.values.flatten.sort,
      "the eight display categories partition exactly the check registry"
    assert_empty OKF::Concept::CONCEPT_SCOPED_CHECKS - OKF::Bundle::Linter::CHECKS,
      "a stale id in CONCEPT_SCOPED_CHECKS silently stops Concept#lint running it"
  end

  # ── Freshness: expired (§5.5, clock-gated) ──────────────────────────────────

  test "expired fires on the stale_after day itself, never the day before" do
    write("dated.md", "---\ntype: Note\ntitle: D\ndescription: d\nstale_after: 2026-09-23\n---\n\na body long enough to skip the stub check\n")

    assert_empty paths(:expired, today: Date.new(2026, 9, 22))
    assert_equal %w[dated.md], paths(:expired, today: Date.new(2026, 9, 23))
    finding = checks(:expired, today: Date.new(2026, 9, 24)).first
    assert_equal({ stale_after: "2026-09-23", days_past: 1 }, finding[:metric])
    assert_equal :info, finding[:severity]
  end

  test "an unparseable stale_after never reads as expired" do
    write("vague.md", "---\ntype: Note\ntitle: V\ndescription: d\nstale_after: next spring\n---\n\na body long enough to skip the stub check\n")

    assert_empty paths(:expired, today: Date.new(2099, 1, 1))
  end

  test "without a today the expired check does not run — and confesses" do
    write("dated.md", "---\ntype: Note\ntitle: D\ndescription: d\nstale_after: 2000-01-01\n---\n\na body long enough to skip the stub check\n")

    result = report
    assert_empty result.findings.select { |f| f[:check] == :expired }
    assert_equal %i[expired stale], result.stats[:skipped_checks],
      "a gate that is sometimes absent and does not confess converts unchecked into checked-and-fine"

    ran = report(today: Date.new(2026, 1, 1), stale_before: Time.iso8601("1990-01-01T00:00:00Z"))
    assert_equal [], ran.stats[:skipped_checks]
  end

  test "stale reads generated_at, so the v0.1 timestamp fallback still feeds it" do
    write("legacy.md", fm(title: "L", timestamp: "2000-01-01") + "a body long enough to skip the stub check\n")
    write("modern.md",
      "---\ntype: Note\ntitle: M\ndescription: d\ngenerated:\n  by: human:x\n  at: 2000-01-01\n---\n\na body long enough to skip the stub check\n")

    assert_equal %w[legacy.md modern.md], paths(:stale, stale_before: Time.iso8601("2015-01-01T00:00:00Z"))
  end

  # ── Provenance: keyed attribution (§5.1) ────────────────────────────────────

  test "unattributed_claim warns per unmatched footnote label, deduplicated" do
    write("doc.md", <<~MD)
      ---
      type: Note
      title: Doc
      description: d
      sources:
        - id: present
          resource: https://e.com/present
      ---

      Claim one.[^missing] Claim two, same source.[^missing] Fine claim.[^present]

      [^present]: a definition line's leading token is not a reference
    MD

    findings = checks(:unattributed_claim)
    assert_equal 1, findings.size, "one unmatched label yields one finding, not one per use"
    assert_equal "doc.md", findings.first[:path]
    assert_equal :warn, findings.first[:severity]
    assert_empty paths(:unused_reference_def), "footnote definitions are not reference definitions"
  end

  test "unused_source informs for a keyed source no footnote cites; id-less sources never participate" do
    write("doc.md", <<~MD)
      ---
      type: Note
      title: Doc
      description: d
      sources:
        - id: cited
          resource: https://e.com/cited
        - id: uncited
          resource: https://e.com/uncited
        - resource: https://e.com/no-id
      ---

      A claim.[^cited]
    MD

    findings = checks(:unused_source)
    assert_equal [ "uncited" ], findings.map { |f| f[:metric][:id] }
    assert_equal :info, findings.first[:severity]
  end

  test "a source cited only by its own definition line still counts as unused" do
    write("doc.md", <<~MD)
      ---
      type: Note
      title: Doc
      description: d
      sources:
        - id: ghost
          resource: https://e.com/ghost
      ---

      No claim cites it.

      [^ghost]: only the definition line names the label
    MD

    assert_equal 1, checks(:unused_source).size
  end

  # ── Provenance: the §7 actor forms on the two identity fields ───────────────

  test "unprefixed_actor informs on both §7 identity fields, each with its own consequence" do
    write("bare.md", "---\ntype: Note\ntitle: B\ndescription: d\nverified: { by: owner }\n---\n\na body long enough to skip the stub check\n")
    write("gen.md", "---\ntype: Note\ntitle: G\ndescription: d\ngenerated: { by: owner }\n---\n\na body long enough to skip the stub check\n")
    write("fine.md", <<~MD)
      ---
      type: Note
      title: F
      description: d
      generated: { by: tooling/1.0 }
      sources:
        - id: s
          resource: https://e.com/s
          author: team:docs
      verified:
        - by: human:ahormati
        - by: process:nightly
        - by: reference_agent/gemini-2.5-pro
      ---

      a body long enough to skip the stub check[^s]
    MD

    findings = checks(:unprefixed_actor)
    assert_equal %w[bare.md gen.md], findings.map { |f| f[:path] }.sort,
      "sources[].author stays out — the SPEC's own examples use team:<id> there"
    assert(findings.all? { |f| f[:severity] == :info }, "it must inform, never block")
    verified = findings.find { |f| f[:path] == "bare.md" }
    generated = findings.find { |f| f[:path] == "gen.md" }
    assert_match(/verified\.by `owner`/, verified[:message])
    assert_match(/reads as machine-confirmed/, verified[:message], "the §5.3 misread is verified.by's consequence")
    assert_match(/generated\.by `owner`/, generated[:message])
    assert_match(/cannot tell a person from a process/, generated[:message],
      "generated.by feeds no tier, so its consequence is the audit trail")
    assert_equal "generated.by", generated[:metric][:field]
  end

  # ── Attestation (§10.2/§10.3) ───────────────────────────────────────────────

  test "incomplete_computation warns on neither and on both, with two messages" do
    write("neither.md", "---\ntype: Attested Computation\ntitle: N\ndescription: d\nruntime: bigquery\n---\n\na body long enough to skip the stub check\n")
    write("both.md", <<~MD)
      ---
      type: Attested Computation
      title: B
      description: d
      runtime: bigquery
      computation: references/computations/x.sql
      ---

      # Computation

      ```sql
      SELECT 1
      ```
    MD
    write("inline.md", "---\ntype: Attested Computation\ntitle: I\ndescription: d\nruntime: bigquery\n---\n\n# Computation\n\n```sql\nSELECT 1\n```\n")
    write("declared.md",
      "---\ntype: Attested Computation\ntitle: D\ndescription: d\nruntime: bigquery\n" \
      "computation: references/computations/x.sql\n---\n\na body long enough to skip the stub check\n")

    findings = checks(:incomplete_computation)
    assert_equal %w[both.md neither.md], findings.map { |f| f[:path] }.sort
    assert_match(/no computation \(neither/, findings.find { |f| f[:path] == "neither.md" }[:message])
    assert_match(/twice/, findings.find { |f| f[:path] == "both.md" }[:message])
    assert(findings.all? { |f| f[:severity] == :warn })
  end

  test "incomplete_computation no longer polices runtime — that moved to the validator" do
    write("no-runtime.md",
      "---\ntype: Attested Computation\ntitle: R\ndescription: d\ncomputation: references/x.sql\n---\n\na body long enough to skip the stub check\n")

    assert_empty checks(:incomplete_computation)
  end

  # ── Migration (§13.1) ───────────────────────────────────────────────────────

  test "the Migration findings are one per bundle, info, with the members in the metric" do
    write("a.md", fm(title: "A", timestamp: "2026-01-01") + "a body long enough to skip the stub check\n")
    write("b.md", fm(title: "B") + "prose\n\n# Citations\n\n[1] [x](https://e.com/x)\n")
    write("c.md", "---\ntype: Note\ntitle: C\ndescription: d\ngenerated:\n  by: human:x\n  at: 2026-01-01\n---\n\na body long enough to skip the stub check\n")

    timestamps = checks(:legacy_timestamp)
    citations = checks(:legacy_citations)
    assert_equal 1, timestamps.size
    assert_equal 1, citations.size
    assert_nil timestamps.first[:path]
    assert_equal [ "a.md" ], timestamps.first[:metric][:concepts]
    assert_equal [ "b.md" ], citations.first[:metric][:concepts]
    assert((timestamps + citations).all? { |f| f[:severity] == :info },
      "--fail-on warn must not turn red on a bundle §13 says is consumable forever")
    assert_match(/generated: \{ by: <actor>/, timestamps.first[:message])
    assert_match(/sources/, citations.first[:message])
  end

  test "a fully migrated bundle emits zero Migration findings" do
    write("c.md", "---\ntype: Note\ntitle: C\ndescription: d\ngenerated:\n  by: human:x\n  at: 2026-01-01\n---\n\na body long enough to skip the stub check\n")

    assert_empty checks(:legacy_timestamp)
    assert_empty checks(:legacy_citations)
  end

  # ── the trust/status posture stats ──────────────────────────────────────────

  test "stats carry the trust distribution in wire spelling and the effective-status frequency" do
    write("u.md", fm(title: "U") + "a body long enough to skip the stub check\n")
    write("m.md", "---\ntype: Note\ntitle: M\ndescription: d\nverified:\n  by: process:x\n---\n\na body long enough to skip the stub check\n")
    write("h.md", "---\ntype: Note\ntitle: H\ndescription: d\nstatus: draft\nverified:\n  by: human:x\n---\n\na body long enough to skip the stub check\n")

    stats = report.stats
    assert_equal({ "unverified" => 1, "machine-confirmed" => 1, "human-reviewed" => 1 }, stats[:trust])
    assert_equal({ "stable" => 2, "draft" => 1 }, stats[:status])
  end

  test "a prose-only v0.1 Citations section still silences uncited_external" do
    write("prose.md", fm(title: "P") + "see [x](https://e.com/x)\n\n# Citations\n\nSee the Q3 finance report.\n")

    assert_empty paths(:uncited_external),
      "the concept recorded provenance — just not as links — and firing would fault every such v0.1 file"
  end

  test "today: coerces a Time or an ISO string and refuses anything else by name" do
    write("dated.md", "---\ntype: Note\ntitle: D\ndescription: d\nstale_after: 2026-09-23\n---\n\na body long enough to skip the stub check\n")

    assert_equal %w[dated.md], paths(:expired, today: "2026-09-23")
    assert_equal %w[dated.md], paths(:expired, today: Time.utc(2026, 9, 23, 12))
    error = assert_raises(ArgumentError) { report(today: :tomorrow) }
    # "by name" is the class's name: an unparseable *string* is the one case
    # the value is worth echoing, and a value of the wrong kind entirely is
    # answered by naming the kind it should have been.
    assert_match(/today: must be a Date \(got Symbol\)/, error.message)

    string_error = assert_raises(ArgumentError) { report(today: "not-a-date") }
    assert_match(/today: must be a Date or a YYYY-MM-DD string \(got "not-a-date"\)/, string_error.message)
  end

  test "broken_attestation_ref reads §10's keys only on the type §10 governs" do
    # §4.1 lets a producer add any frontmatter key, so `computation:` on a
    # Recipe means whatever that producer decided. Warning about it fails a
    # --fail-on warn gate over a key §10 does not govern for that concept —
    # the same line check_incomplete_computation already draws.
    write("recipe.md", "---\ntype: Recipe\ntitle: R\ndescription: d\n" \
                       "computation: /steps/does-not-exist.md\n---\n\na body long enough to skip the stub check\n")
    write("real.md", "---\ntype: Attested Computation\ntitle: A\ndescription: d\nruntime: bigquery\n" \
                     "computation: /steps/does-not-exist.md\n---\n\na body long enough to skip the stub check\n")

    assert_equal %w[real.md], paths(:broken_attestation_ref),
      "the same dangling path, reported on the Attested Computation and not on the Recipe"
  end

  test "a human: actor with a malformed id is not told it reads as machine-confirmed" do
    # §5.3 derives the tier from the `human:` prefix alone, so `human:jane doe`
    # is already human-reviewed however malformed the id is. Saying it "reads
    # as machine-confirmed" contradicted the same run's own trust stat and sent
    # the reader to fix a tier that was never wrong.
    write("signed.md", "---\ntype: Note\ntitle: S\ndescription: d\n" \
                       "verified:\n  - by: 'human:jane doe'\n---\n\na body long enough to skip the stub check\n")

    result = report
    finding = checks(:unprefixed_actor).first

    refute_nil finding, "the id still matches none of §7's forms, so the finding stands"
    refute_match(/machine-confirmed/, finding[:message],
      "the prefix already reads as human-reviewed — the same report's trust stat says so")
    assert_equal 1, result.stats[:trust]["human-reviewed"],
      "the tier the message must not contradict"
  end

  test "plain footnotes on a concept with no keyed sources are prose, not a warn" do
    # §5.1 does not reserve footnotes for attribution: a document using
    # ordinary GFM footnotes, with no sources[].id anywhere, has not adopted
    # keyed attribution — faulting it would gate --fail-on warn on a writing
    # style. The same rule check_unused_source already states from the other
    # side.
    write("essay.md", fm(title: "E") + "A claim.[^note]\n\n[^note]: just a footnote, no sources at all\n")
    write("keyed.md", <<~MD)
      ---
      type: Note
      title: K
      description: d
      sources:
        - id: real
          resource: https://e.com/real
      ---

      A claim.[^typo] — undefined and unmatched, so it still warns

    MD

    assert_equal %w[keyed.md], paths(:unattributed_claim)
  end

  test "adjacent footnote references are not an undefined reference-style link" do
    # `[^rev][^audit]` parses as a REFERENCE_LINK text/label pair, and
    # DEFINITION rightly refuses caret labels — so a well-formed doc with two
    # adjacent footnotes earned a false undefined_reference warn.
    write("doc.md", <<~MD)
      ---
      type: Note
      title: D
      description: d
      sources:
        - id: rev
          resource: https://e.com/rev
        - id: audit
          resource: https://e.com/audit
      ---

      Confirmed twice.[^rev][^audit]

      [^rev]: the review
      [^audit]: the audit
    MD

    assert_empty paths(:undefined_reference)
    assert_empty paths(:unattributed_claim)
  end

  test "the footnote-to-source join folds case the way GFM renders it" do
    write("cased.md", <<~MD)
      ---
      type: Note
      title: C
      description: d
      sources:
        - id: R1
          resource: https://e.com/r1
      ---

      A claim.[^r1]
    MD

    assert_empty paths(:unattributed_claim), "GitHub renders this attribution; the join must agree"
    assert_empty paths(:unused_source)
  end

  test "a source cited only inside another footnote's definition prose is not unused" do
    write("doc.md", <<~MD)
      ---
      type: Note
      title: D
      description: d
      sources:
        - id: a
          resource: https://e.com/a
        - id: b
          resource: https://e.com/b
      ---

      A claim.[^a]

      [^a]: see also [^b]
    MD

    assert_empty paths(:unused_source), "only the leading definition token is not a reference; its prose is"
    assert_empty paths(:unattributed_claim)
  end

  test "the library refuses an unknown check id instead of running nothing and reporting fine" do
    write("a.md", fm(title: "A") + "hi\n")

    error = assert_raises(ArgumentError) { report(only: [ :broken_citation ]) }
    assert_match(/unknown check\(s\): broken_citation/, error.message)
    assert_raises(ArgumentError) { report(except: [ :missing_timestamp ]) }
  end

  test "a leftover Citations section keeps its warn-level broken targets beside a native sources list" do
    # Half-migrated: the native list took over #sources, but §13.1 keeps the
    # section readable — and on main its broken in-bundle target was a warn.
    # Migration must not downgrade a gate from exit 1 to exit 0.
    write("half.md", <<~MD)
      ---
      type: Note
      title: H
      description: d
      sources:
        - resource: https://e.com/native
      ---

      prose

      # Citations

      [1] [old ref](/nope.md)
    MD

    findings = checks(:broken_source)
    assert_equal %w[half.md], findings.map { |f| f[:path] }
    assert_equal :warn, findings.first[:severity]
  end

  test "two files pinning the same custom id do not cross-contaminate the footnote joins" do
    write("a.md", <<~MD)
      ---
      type: Note
      title: A
      id: shared
      description: d
      sources:
        - id: y
          resource: https://e.com/y
      ---

      no footnotes here, so y is unused
    MD
    write("b.md", <<~MD)
      ---
      type: Note
      title: B
      id: shared
      description: d
      sources:
        - id: z
          resource: https://e.com/z
      ---

      cites its own source.[^z]
    MD

    assert_equal 1, checks(:unused_source).size,
      "the label cache must key on the path (unique by construction), not a producer-pinned id"
  end

  test "an image alt starting with a caret is not a footnote reference" do
    write("doc.md", <<~MD)
      ---
      type: Note
      title: D
      description: d
      sources:
        - id: real
          resource: https://e.com/real
      ---

      A diagram: ![^diagram](d.png) and a real citation.[^real]
    MD

    assert_empty paths(:unattributed_claim)
  end

  test "an adopter can still carry an ordinary GFM content footnote" do
    # §5.1 never reserves every [^label] for attribution: a label with its own
    # definition line is a self-contained content footnote that renders fine —
    # the dangling ones (no definition, no source id) are the misattributions.
    write("doc.md", <<~MD)
      ---
      type: Note
      title: D
      description: d
      sources:
        - id: bq
          resource: https://e.com/bq
      ---

      A cited claim.[^bq] An aside.[^note] A dangling one.[^ghost]

      [^note]: ordinary explanatory footnote, defined right here
    MD

    findings = checks(:unattributed_claim)
    assert_equal [ "ghost" ], findings.map { |f| f[:metric][:label] },
      "defined content footnotes pass; only the undefined, unmatched label warns"
  end

  test "the status distribution folds case the way every filter surface does" do
    write("a.md", fm(title: "A") + "a body long enough to skip the stub check\n")
    write("b.md", "---\ntype: Note\ntitle: B\ndescription: d\nstatus: Draft\n---\n\na body long enough to skip the stub check\n")
    write("c.md", "---\ntype: Note\ntitle: C\ndescription: d\nstatus: draft\n---\n\na body long enough to skip the stub check\n")

    assert_equal({ "draft" => 2, "stable" => 1 }, report.stats[:status],
      "--status draft narrows both concepts into one bucket; the posture inventory must reconcile with it")
  end

  private

  def report(**options)
    OKF::Bundle::Linter.call(OKF::Bundle::Reader.read(@tmpdir), **options)
  end

  def checks(name, **options)
    report(**options).findings.select { |finding| finding[:check] == name }
  end

  def paths(name, **options)
    checks(name, **options).map { |finding| finding[:path] }.sort
  end

  def fm(title: "T", type: "Note", description: "d", timestamp: nil)
    lines = [ "type: #{type}" ]
    lines << "title: #{title}" unless title.nil?
    lines << "description: #{description}" unless description.nil?
    lines << "timestamp: #{timestamp}" unless timestamp.nil?
    "---\n#{lines.join("\n")}\n---\n\n"
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
