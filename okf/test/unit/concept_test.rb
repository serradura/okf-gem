# frozen_string_literal: true

require "test_helper"
require "okf"

# OKF::Concept as a pure, in-memory value object — constructed straight from data
# (the Rails path) and interrogated without any disk access.
class OKF::ConceptTest < OKF::TestCase
  def build(frontmatter, body = "x")
    OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note" }.merge(OKF::Markdown::Frontmatter.stringify_keys(frontmatter)), body: body)
  end

  test "derives id from path and reads typed frontmatter accessors" do
    concept = OKF::Concept.new(
      path: "tables/orders.md",
      frontmatter: { type: "BigQuery Table", title: "Orders", description: "d", tags: [ "sales" ], timestamp: "2026-01-01" },
      body: "# Orders\n"
    )

    assert_equal "tables/orders", concept.id
    assert_equal "BigQuery Table", concept.type
    assert_equal "Orders", concept.title
    assert_equal "d", concept.description
    assert_equal [ "sales" ], concept.tags
    assert_equal "2026-01-01", concept.timestamp
  end

  test "prefers an explicit frontmatter id, falling back to the path when blank" do
    pinned = OKF::Concept.new(path: "tables/orders.md", frontmatter: { "id" => "orders", "type" => "Table" }, body: "x")
    blank = OKF::Concept.new(path: "tables/orders.md", frontmatter: { "id" => "  ", "type" => "Table" }, body: "x")

    assert_equal "orders", pinned.id
    assert_equal "tables/orders", blank.id
  end

  test "extracts cross-links from the body" do
    concept = OKF::Concept.new(
      path: "a.md",
      frontmatter: { "type" => "Note" },
      body: "see [b](/b.md) and [site](https://ex.com)\n\n# Citations\n\n[1] [src](https://ex.com/paper)\n"
    )

    assert_equal [ "/b.md", "https://ex.com", "https://ex.com/paper" ], concept.links
    assert_equal [ "https://ex.com", "https://ex.com/paper" ], concept.external_links
  end

  test "to_markdown round-trips through Frontmatter.parse" do
    concept = OKF::Concept.new(
      path: "a.md",
      frontmatter: { "type" => "Note", "title" => "A" },
      body: "# A\n\nbody\n"
    )

    frontmatter, body = OKF::Markdown::Frontmatter.parse(concept.to_markdown)
    assert_equal "Note", frontmatter["type"]
    assert_equal "A", frontmatter["title"]
    assert_equal "# A\n\nbody\n", body
  end

  test "lint runs the concept-scoped checks only — no orphan/backlog for a lone concept" do
    concept = OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note" }, body: "x")
    report = concept.lint

    checks = report.findings.map { |f| f[:check] }
    assert_includes checks, :missing_title
    assert_includes checks, :stub
    refute_includes checks, :orphan
    refute_includes checks, :missing_concept
  end

  test "reserved? recognizes index.md and log.md at any depth" do
    assert OKF::Concept.reserved?("index.md")
    assert OKF::Concept.reserved?("sub/log.md")
    refute OKF::Concept.reserved?("sub/note.md")
  end

  # ── §5.2 generated, and §13.1's timestamp fallback ──

  test "reads generated as a mapping, stringifying its keys" do
    concept = build("generated" => { by: "human:ahormati", at: "2026-06-20T22:53:05Z" })

    assert_equal({ "by" => "human:ahormati", "at" => "2026-06-20T22:53:05Z" }, concept.generated)
    assert_equal "2026-06-20T22:53:05Z", concept.generated_at
    assert_equal "human:ahormati", concept.generated_by
  end

  test "generated is nil when absent, and when it is not a mapping" do
    assert_nil build({}).generated
    assert_nil build("generated" => "2026-06-20").generated
    assert_nil build({}).generated_at
    assert_nil build({}).generated_by
  end

  test "falls back to a v0.1 timestamp when generated is absent (§13.1)" do
    concept = build("timestamp" => "2026-01-01T10:00:00Z")

    assert_equal({ "at" => "2026-01-01T10:00:00Z" }, concept.generated)
    assert_equal "2026-01-01T10:00:00Z", concept.generated_at
  end

  test "a fallback generated carries no actor rather than an invented one" do
    assert_nil build("timestamp" => "2026-01-01").generated_by
  end

  test "a native generated wins over a legacy timestamp when a document carries both" do
    concept = build("generated" => { "by" => "human:x", "at" => "2026-06-20" }, "timestamp" => "2026-01-01")

    assert_equal({ "by" => "human:x", "at" => "2026-06-20" }, concept.generated)
    assert_equal "2026-06-20", concept.generated_at
  end

  test "a non-mapping generated falls back rather than reading nothing" do
    assert_equal({ "at" => "2026-01-01" }, build("generated" => "2026-06-20", "timestamp" => "2026-01-01").generated)
  end

  test "generated_at falls back per-key — by-only generated plus timestamp keeps its date" do
    concept = build("generated" => { "by" => "human:x" }, "timestamp" => "2026-01-01")

    assert_equal "2026-01-01", concept.generated_at
    assert_equal "human:x", concept.generated_by
    assert_equal({ "by" => "human:x" }, concept.generated)
  end

  test "generated.at as a plain date reads cleanly" do
    concept = build("generated" => { "by" => "human:x", "at" => Date.new(2026, 8, 10) })

    assert_equal Date.new(2026, 8, 10), concept.generated_at
  end

  test "declared_generated? answers the raw key, never the fallback" do
    assert build("generated" => { "by" => "human:x" }).declared_generated?
    refute build("timestamp" => "2026-01-01").declared_generated?
    refute build({}).declared_generated?
  end

  # ── §5.2/§5.3 verified and trust tiers ──

  test "reads verified as a list" do
    concept = build("verified" => [ { "by" => "process:nightly", "at" => "2026-06-26T02:00:00Z" } ])

    assert_equal [ { "by" => "process:nightly", "at" => "2026-06-26T02:00:00Z" } ], concept.verified
  end

  test "treats a bare verified mapping as a one-element list (§5.2 MUST)" do
    concept = build("verified" => { "by" => "human:ahormati", "at" => "2026-06-25T09:00:00Z" })

    assert_equal [ { "by" => "human:ahormati", "at" => "2026-06-25T09:00:00Z" } ], concept.verified
  end

  test "drops verified entries that are not mappings, folding degenerate shapes to unverified" do
    assert_equal [ { "by" => "human:x" } ], build("verified" => [ { "by" => "human:x" }, "nope" ]).verified
    assert_equal [], build("verified" => "nope").verified
    assert_equal [], build("verified" => []).verified
    assert_equal :unverified, build("verified" => []).trust_tier
    assert_equal :unverified, build("verified" => [ "nope" ]).trust_tier
  end

  test "derives the three trust tiers from verified (§5.3)" do
    assert_equal :unverified, build({}).trust_tier
    assert_equal :machine_confirmed, build("verified" => { "by" => "reference_agent/gemini-2.5-pro" }).trust_tier
    assert_equal :human_reviewed, build("verified" => { "by" => "human:ahormati" }).trust_tier
  end

  test "one human verifier among machines makes it human-reviewed" do
    concept = build("verified" => [ { "by" => "process:nightly" }, { "by" => "human:ahormati" } ])

    assert_equal :human_reviewed, concept.trust_tier
  end

  # ── §5.1 sources, and §13.1's Citations fallback ──

  test "reads sources as a list of mappings" do
    concept = build("sources" => [ { id: "ga4", resource: "https://ex.com/s", usage_count: 5000 } ])

    assert_equal [ { "id" => "ga4", "resource" => "https://ex.com/s", "usage_count" => 5000 } ], concept.sources
  end

  test "sources is empty when absent and drops non-mapping entries a mapping survives beside" do
    assert_equal [], build({}).sources
    assert_equal [], build("sources" => "https://ex.com").sources
    assert_equal [ { "resource" => "a" } ], build("sources" => [ { "resource" => "a" }, "b" ]).sources
  end

  test "falls back to the v0.1 Citations body list when sources is absent" do
    concept = build({}, "# Citations\n\n[1] [The paper](https://ex.com/paper)\n")

    assert_equal [ { "title" => "The paper", "resource" => "https://ex.com/paper" } ], concept.sources
  end

  test "the fallback fires when the native sources yields no mappings, not merely when the key is absent" do
    body = "# Citations\n\n[1] [The paper](https://ex.com/paper)\n"
    expected = [ { "title" => "The paper", "resource" => "https://ex.com/paper" } ]

    assert_equal expected, build({ "sources" => %w[prod-db warehouse] }, body).sources
    assert_equal expected, build({ "sources" => [] }, body).sources
    assert_equal expected, build({ "sources" => "prod-db" }, body).sources
  end

  test "a citation with no link text yields a source with no title rather than a blank one" do
    concept = build({}, "# Citations\n\n- https://ex.com/paper\n")

    assert_equal [ { "resource" => "https://ex.com/paper" } ], concept.sources
  end

  test "a native sources list wins over a Citations body a document still carries" do
    concept = build({ "sources" => [ { "resource" => "https://ex.com/native" } ] },
      "# Citations\n\n[1] [old](https://ex.com/legacy)\n")

    assert_equal [ { "resource" => "https://ex.com/native" } ], concept.sources
  end

  test "reads both spellings of a half-migrated document, each in its own family" do
    concept = build({ "sources" => [ { "resource" => "https://ex.com/native" } ], "timestamp" => "2026-01-01" }, "x")

    assert_equal "2026-01-01", concept.generated_at
    assert_equal [ { "resource" => "https://ex.com/native" } ], concept.sources
  end

  test "reads usage_window as a mapping, nil otherwise" do
    assert_equal({ "from" => "2026-06-01", "to" => "2026-06-30" },
      build("usage_window" => { from: "2026-06-01", to: "2026-06-30" }).usage_window)
    assert_nil build({}).usage_window
    assert_nil build("usage_window" => "june").usage_window
  end

  # ── §5.4/§5.5 lifecycle ──

  test "status defaults to stable when absent or blank (§5.4)" do
    assert_equal "stable", build({}).status
    assert_equal "stable", build("status" => "   ").status
    assert_nil build({}).declared_status
  end

  test "status reports whatever a producer declared, including a value outside the three" do
    assert_equal "deprecated", build("status" => "deprecated").status
    assert_equal "shipped", build("status" => "shipped").status
    assert_equal "shipped", build("status" => "shipped").declared_status
  end

  test "a padded human: actor still reads human-reviewed, the way the linter reads it" do
    # The linter strips before matching §7's forms, so a quoted `by` with a
    # leading space was told "the `human:` prefix already reads as
    # human-reviewed" by the very report whose trust stat counted it under
    # machine-confirmed — the contradiction actor_consequence exists to end,
    # surviving in the one place the two sides disagreed on whitespace.
    assert_equal "human-reviewed", build("verified" => [ { "by" => "  human:jane doe" } ]).trust
    assert_equal :human_reviewed, build("verified" => [ { "by" => "human:ok\n" } ]).trust_tier
  end

  test "generated and verified are built once, like sources beside them" do
    # Both re-run stringify_keys and allocate on every call, and Bundle#catalog
    # asks four times per row (generated_at and generated_by each read
    # #generated twice, #trust re-walks #verified). The model is immutable once
    # built, which is the same premise #sources memoizes on.
    concept = build("generated" => { "by" => "human:me", "at" => "2026-06-01" },
      "verified" => [ { "by" => "human:you" } ])

    assert_same concept.generated, concept.generated
    assert_same concept.verified, concept.verified
  end

  test "an absent generated is memoized as absent, not recomputed each time" do
    # The nil case is the one a `||=` would silently re-run on every call —
    # and it is the common case, since a bundle mid-migration has no `generated`.
    concept = build({})

    assert_nil concept.generated
    assert_nil concept.generated
    assert_equal({ "at" => "2026-05-28" }, build("timestamp" => "2026-05-28").generated,
      "the §13.1 fallback still answers, and answers the same way twice")
  end

  test "status keeps the producer's spelling; only comparison folds" do
    # Two jobs, two methods, and the split is load-bearing — it has been argued
    # both ways. Everything that *displays* a status shows what the producer
    # wrote (the catalog row is declared_status, so are the card chip and the
    # inspector line), and everything that *narrows* folds, which is what
    # `--status draft` matching `Draft` means. Collapsing them either way makes
    # one surface disagree with the rest.
    concept = build("status" => "Draft")

    assert_equal "Draft", concept.status, "the accessor prints what the CLI and the page print"
    assert_equal "Draft", concept.declared_status
    assert_equal "draft", OKF::Concept.effective_status(concept.declared_status),
      "the comparison fold is a separate method, and it is the one filters use"
    assert_equal "stable", OKF::Concept.effective_status(nil), "which also carries §5.4's default"
  end

  test "a YAML-boolean status reads as the string it serializes to, on every surface" do
    # Psych reads `status: no` as false. OKF.blank?(false) is true, so the old
    # accessor answered "stable" while the row's &.to_s printed "false" — one
    # concept, two answers, and --status stable quietly excluded it.
    concept = build("status" => false)

    assert_equal "false", concept.status
    assert_equal false, concept.declared_status
  end

  test "stale_on? is true on the stale_after day itself, never the day before (§5.5)" do
    concept = build("stale_after" => "2026-09-23")

    refute concept.stale_on?(Date.new(2026, 9, 22))
    assert concept.stale_on?(Date.new(2026, 9, 23))
    assert concept.stale_on?(Date.new(2026, 9, 24))
  end

  test "stale_on? is false when stale_after is absent or unparseable" do
    assert_nil build({}).stale_after_date
    refute build({}).stale_on?(Date.new(2026, 9, 23))
    assert_nil build("stale_after" => "next spring").stale_after_date
    refute build("stale_after" => "next spring").stale_on?(Date.new(2026, 9, 23))
  end

  test "accepts a stale_after that Psych already parsed into a Date" do
    concept = build("stale_after" => Date.new(2026, 9, 23))

    assert_equal Date.new(2026, 9, 23), concept.stale_after_date
    assert concept.stale_on?(Date.new(2026, 9, 23))
  end

  # ── §10 attested computation ──

  test "recognizes the Attested Computation type and reads its contract" do
    concept = OKF::Concept.new(
      path: "c.md",
      frontmatter: {
        "type" => "Attested Computation",
        "runtime" => "bigquery",
        "computation" => "references/computations/revenue.sql",
        "parameters" => [ { name: "year", type: "integer", required: true }, "nope" ],
        "executor" => { resource: "references/skills/run-on-bq.md", receipt: [ "job_id" ] },
        "attester" => { resource: "references/attesters/revenue.py" }
      },
      body: "x"
    )

    assert concept.attested_computation?
    assert_equal "bigquery", concept.runtime
    assert_equal "references/computations/revenue.sql", concept.computation
    assert_equal [ { "name" => "year", "type" => "integer", "required" => true } ], concept.parameters
    assert_equal({ "resource" => "references/skills/run-on-bq.md", "receipt" => [ "job_id" ] }, concept.executor)
    assert_equal({ "resource" => "references/attesters/revenue.py" }, concept.attester)
  end

  test "a plain concept is not an attested computation and carries none of its fields" do
    concept = build({})

    refute concept.attested_computation?
    assert_nil concept.runtime
    assert_nil concept.computation
    assert_equal [], concept.parameters
    assert_nil concept.executor
    assert_nil concept.attester
  end

  test "the type match is exact — producer-defined types are never folded (§4.1)" do
    refute build("type" => "attested computation").attested_computation?
  end

  # ── detection (lint's, never reading's) ──

  test "detects the two legacy spellings for lint" do
    legacy = build({ "timestamp" => "2026-01-01" }, "# Citations\n\n[1] [x](https://e.com)\n")
    modern = build("generated" => { "by" => "human:x" })

    assert legacy.legacy_timestamp?
    assert legacy.legacy_citations?
    refute modern.legacy_timestamp?
    refute modern.legacy_citations?
  end

  # ── the §13.1 whole: a pure v0.1 document answers every v0.2 question ──

  test "a pure v0.1 document answers every v0.2 question" do
    concept = OKF::Concept.new(
      path: "a.md",
      frontmatter: { "type" => "Note", "timestamp" => "2026-01-01T10:00:00Z" },
      body: "prose\n\n# Citations\n\n[1] [The paper](https://ex.com/paper)\n"
    )

    assert_equal({ "at" => "2026-01-01T10:00:00Z" }, concept.generated)
    assert_equal [ { "title" => "The paper", "resource" => "https://ex.com/paper" } ], concept.sources
    assert_equal [], concept.verified
    assert_equal :unverified, concept.trust_tier
    assert_equal "stable", concept.status
    refute concept.declared_generated?
  end

  test "block-style YAML reads identically to flow style, family by family" do
    doc = <<~MD
      ---
      type: Metric
      generated:
        by: reference_agent/gemini-2.5-pro
        at: 2026-06-20
      verified:
        - by: human:ahormati
          at: 2026-06-25
      sources:
        - id: ga4
          resource: https://ex.com/s
          usage_count: 5000
      usage_window:
        from: 2026-06-01
        to: 2026-06-30
      parameters:
        - name: year
          type: integer
          required: true
      executor:
        resource: references/skills/run.md
      attester:
        resource: references/attesters/check.py
      ---

      x
    MD
    frontmatter, body = OKF::Markdown::Frontmatter.parse(doc)
    concept = OKF::Concept.new(path: "a.md", frontmatter: frontmatter, body: body)

    assert_equal "reference_agent/gemini-2.5-pro", concept.generated_by
    assert_equal Date.new(2026, 6, 20), concept.generated_at
    assert_equal :human_reviewed, concept.trust_tier
    assert_equal [ { "id" => "ga4", "resource" => "https://ex.com/s", "usage_count" => 5000 } ], concept.sources
    assert_equal({ "from" => Date.new(2026, 6, 1), "to" => Date.new(2026, 6, 30) }, concept.usage_window)
    assert_equal [ { "name" => "year", "type" => "integer", "required" => true } ], concept.parameters
    assert_equal({ "resource" => "references/skills/run.md" }, concept.executor)
    assert_equal({ "resource" => "references/attesters/check.py" }, concept.attester)
  end

  test "the class-level v0.2 facts are constants the other layers read" do
    assert_equal %w[0.2 0.1], OKF::Concept::KNOWN_SPEC_VERSIONS
    assert_equal %w[draft stable deprecated], OKF::Concept::STATUSES
    assert_equal "stable", OKF::Concept::DEFAULT_STATUS
    assert_equal "human:", OKF::Concept::HUMAN_ACTOR
    assert_equal "Attested Computation", OKF::Concept::ATTESTED_COMPUTATION
  end
  test "stale_after_date refuses a DateTime the way the validator does" do
    # DateTime < Date, so a bare is_a?(Date) guard admitted the one temporal
    # class the strict-YYYY-MM-DD contract excludes — lint said expired, the
    # validator said malformed, and the page's regex said fresh.
    concept = build("stale_after" => DateTime.new(2020, 1, 1, 10))

    assert_nil concept.stale_after_date
    refute concept.stale_on?(Date.new(2026, 1, 1))
  end
end
