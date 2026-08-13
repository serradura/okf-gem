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
      unused_source: :info, missing_generated_by: :info, unprefixed_actor: :info,
      incomplete_computation: :warn,
      legacy_timestamp: :info, legacy_citations: :info,
      duplicate_title: :info, unused_reference_def: :info, undefined_reference: :warn, self_link: :info
    }

    assert_equal expected, OKF::Bundle::Linter::SEVERITIES
    assert_equal OKF::Bundle::Linter::CHECKS.sort, OKF::Bundle::Linter::SEVERITIES.keys.sort,
      "every check has exactly one pinned severity"
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

      [^missing]: a definition line is not a reference
      [^present]: nor is this one
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

  test "missing_generated_by asks the declared generated, never the lifted one" do
    write("actorless.md", "---\ntype: Note\ntitle: A\ndescription: d\ngenerated: { at: 2026-01-01 }\n---\n\na body long enough to skip the stub check\n")
    write("legacy.md", fm(title: "L", timestamp: "2026-01-01") + "a body long enough to skip the stub check\n")

    assert_equal %w[actorless.md], paths(:missing_generated_by)
  end

  # ── Provenance: the §7 actor forms on verified[].by ─────────────────────────

  test "unprefixed_actor informs on a verified.by outside §7's three forms, and only there" do
    write("bare.md", "---\ntype: Note\ntitle: B\ndescription: d\nverified: { by: owner }\n---\n\na body long enough to skip the stub check\n")
    write("fine.md", <<~MD)
      ---
      type: Note
      title: F
      description: d
      generated: { by: owner-tool }
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
    assert_equal %w[bare.md], findings.map { |f| f[:path] }
    assert_equal :info, findings.first[:severity], "it must inform, never block"
    assert_match(/reads as machine-confirmed/, findings.first[:message])
    assert_match(/human:<id>/, findings.first[:message])
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
    assert_match(/today: must be a Date/, error.message)
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
