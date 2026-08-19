---
type: Format
title: OKF v0.2 — what changed from v0.1
description: The trust, provenance, lifecycle and attestation families v0.2 adds, the two v0.1 spellings it retires, and how narrowly the gem is coupled to either.
resource: https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md
tags: [okf, conformance, provenance]
generated:
  by: human:maintainer
  at: 2026-08-13T12:00:00Z
sources:
  - id: upstream-spec
    title: SPEC.md (upstream)
    resource: https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md
  - id: announcement
    title: OKF v0.2 adds trust signals
    resource: https://cloud.google.com/blog/products/data-analytics/okf-v0-2-adds-trust-signals
---

# Overview

OKF v0.2 was published on 2026-07-24,[^announcement] and the gem targets it: the
[vendored spec](okf-format.md) is the published v0.2 — 1003 upstream lines at
commit `3fcbb9f`, no longer a draft.

The premise moved. v0.1 assumed a corpus authored once and read many times; v0.2
assumes one **written continuously by agents and consumed by different agents**,
and makes first-class the five questions that premise raises — provenance, trust,
freshness, lifecycle, and attestation. Every answer is an optional frontmatter
family, so a v0.1 concept that gains nothing is still a valid v0.2 concept.

**Exactly two v0.1 spellings are retired**, and they are the whole of what a
migration must mechanically rewrite:

| Retired | Replacement | Fallback the spec permits |
|---------|-------------|---------------------------|
| `timestamp` | `generated: { by, at }` (§5.2) | consumers **MAY** read a legacy `timestamp` when `generated` is absent |
| body `# Citations` | `sources` frontmatter (§5.1) | consumers **SHOULD** read `sources` and **MAY** still parse the v0.1 body list |

Both fallbacks are sanctioned by §13.1, which is what makes reading v0.1 and
targeting v0.2 a compatible pair rather than a choice.

# Frontmatter fields

| Field | v0.1 | v0.2 | Change |
|-------|------|------|--------|
| `type` | REQUIRED | REQUIRED | same — v0.2 adds `Attested Computation` to the examples and names it the only always-required key |
| `title` `description` `resource` `tags` | recommended | recommended | same |
| `timestamp` | recommended | — | **removed**, superseded by `generated.at` |
| `generated` | — | `{ by, at }`; `by` REQUIRED within, an actor (§7) | **new** |
| `verified` | — | list of `{ by, at }`; a bare mapping is a one-element list | **new** |
| `sources` | — | list of `{ resource, id, title, author, usage_count, last_modified }`; `resource` REQUIRED within an entry | **new** |
| `usage_window` | — | `{ from, to }`, a sibling of `sources`; an entry MAY override it | **new** |
| `status` | — | `draft` \| `stable` \| `deprecated`; absent ⇒ `stable` | **new** |
| `stale_after` | — | absolute `YYYY-MM-DD`; stale when `today >= stale_after` | **new** |
| `runtime` | — | REQUIRED for `type: Attested Computation`; fixes what `parameters` mean | **new** |
| `parameters` | — | list of `{ name, type, required }` | **new** |
| `computation` | — | path to a computation file, used instead of the body fence | **new** |
| `executor` | — | `{ resource, receipt }` — run instructions, and the fields a run must return | **new** |
| `attester` | — | `{ resource }` — deterministic, no-LLM code that judges a receipt | **new** |
| `okf_version` | root `index.md` only, `"0.1"` | root `index.md` only, `"0.2"` | value only |
| unknown keys | consumers **SHOULD NOT** reject | consumers **MUST NOT** reject | hardened |

One of these landed where this gem had already improvised. `status` is passed
through as a free-form producer key, and the graph page (`@okf-kernel capabilities/render`)
styles the value `shipped` specially — legal under §4.1, which lets a producer
use any value, but not one of the three v0.2 names. The special case is narrower
than it looks: **no concept in this bundle and no test fixture declares `status`
at all**, so nothing here currently reaches it. Adopting §5.4 is therefore a
choice about the page's vocabulary, not a migration of any content.

# Body conventions

| Heading | v0.1 | v0.2 |
|---------|------|------|
| `# Schema` `# Examples` | conventional | conventional |
| `# Computation` | — | **new** — the sanctioned computation of an Attested Computation (§10) |
| `# Citations` | conventional (§8) | **removed** — provenance moves to `sources`, and per-claim attribution to a markdown footnote whose label is a `sources[].id` |

Keying attribution on a stable `id` rather than a position (`sources[0]`) is
argued in §5.1 from the same premise as the rest: agents rewrite these documents
constantly, and a positional index misattributes silently the moment the list is
reordered.

# Document structure

| v0.1 | v0.2 | Change |
|------|------|--------|
| §1 Motivation | §1 | rewritten around the five questions |
| §2 Terminology | §2 | **+** Source, Provenance, Credibility signal, Actor, Trust tier, Attested Computation, Executor, Receipt, Attester · **−** Citation |
| §3 Bundle Structure, §3.1 Reserved | §3, §3.1 | unchanged |
| §4 Concept Documents | §4 | the field families above |
| — | **§5 Provenance, trust, lifecycle** | new — `sources` and its credibility signals, `generated`/`verified`, trust tiers, `status`, `stale_after` |
| §5 Cross-linking | §6 | renumbered · **+** §6.2 path-valued fields, **+** §6.3 the `references/` convention |
| — | **§7 Actor convention** | new — `<producer>/<version>`, `human:<id>`, `process:<id>` |
| §6 Index Files | §8 | renumbered; the frontmatter exception is now stated inline |
| §7 Log Files | §9 | renumbered, substance unchanged |
| §8 Citations | — | **dropped** into §5.1 |
| — | **§10 Attested computations** | new — the standalone-concept argument, contract fields, inline-vs-file, the consumer flow, verification vs attestation |
| §9 Conformance | §11 | the three hard conditions are unchanged; new consumer obligations |
| §10 Relationship to other formats | — | **dropped** |
| §11 Versioning | §12 | **+** "Considered and deferred": the runtime protocol, the attester ABI and sandboxing, attestation caching, semantic-layer templates |
| — | **§13 Changes from v0.1** | new — the normative migration notes |
| Appendix A — Minimal example bundle | Appendix A: Worked example, an income statement | replaced by a v0.1 and v0.2 form of the same document, side by side |

# Normative language

| Rule | v0.1 | v0.2 |
|------|------|------|
| Unrecognized frontmatter keys | SHOULD NOT reject | **MUST NOT** reject |
| A bare `verified` mapping | — | **MUST** be read as a one-element list |
| A missing optional family | — | **MUST NOT** be grounds to reject a concept |
| Trust tiers and staleness | — | **SHOULD** be derived only from the specified fields |
| A failing attestation | — | **SHOULD** be surfaced, never silently dropped |
| The `human:` prefix | — | producers **MUST** use it for hand-authored or human-confirmed content |
| Index frontmatter | §6 says none; §11 says the root MAY carry `okf_version` — **a contradiction** | §8 states the exception inline |
| Conformance conditions | three | the same three, verbatim |

The [conformance gate](okf-format.md) is therefore untouched: v0.2 renumbers
it to §11 and adds obligations that all point the same way the old ones did —
*tolerate more*, never reject more.

# Trust is derived, never stored

| `verified` | Tier |
|------------|------|
| key absent | unverified |
| present, non-`human:` actors only | machine-confirmed |
| present, at least one `human:<id>` | human-reviewed |

§5.1 makes the same move for source credibility: OKF records objective signals —
`author`, `usage_count`, `last_modified` — and never a score, because a score is
subjective, unportable between consumers, and goes stale while the facts behind
it do not. `usage_count` is explicitly coarse: comparable at the
alive-versus-dead and order-of-magnitude level and against a source's own
history, not as a cross-kind ranking, since a scheduled query's executions and a
human's deliberate dashboard views do not weigh the same.

# How narrowly the gem is coupled

Measured across `lib/`, not estimated. The v0.1 surface is **two accessors and
one module**:

| Spelling | Sites | All reached through |
|----------|-------|---------------------|
| `timestamp` | 6 — the catalog row, two lint checks, the validator's ISO warning, `ROW_FIELDS`, the graph page's badge | `OKF::Concept#timestamp` |
| `# Citations` | 3 — `Concept#citations`, `uncited_external`, `broken_citation` | `OKF::Markdown::Citations` |
| `okf_version` | 1 — the root-index frontmatter check | `OKF::Bundle::Validator` |

Not one of them reads `frontmatter["timestamp"]` directly, which is what makes a
single read-time normalization on Concept (`@okf-kernel model/concept`) sufficient: both
v0.1 shapes map *into* v0.2 shapes losslessly, so everything downstream can be
taught exactly one shape.

Search (`@okf-kernel capabilities/search`) and the graph payload are **structurally
immune** — `Bundle::Graph#node` emits `id`/`type`/`title`/`description`/`tags`
and `Bundle::Search#row` emits those plus `dir`/`top_dir`/`matched`/`score`/
`snippet`. Neither carries a timestamp or touches citations, so neither changes.

The gem targets v0.2 now, and the narrowness above is what let the support land
as one reading rule instead of a version hierarchy:
Concept (`@okf-kernel model/concept`) stays one class whose accessors carry §13.1's
two fallbacks inline, the validator (`@okf-kernel capabilities/validator`) warns on
the new families' shapes, and the linter (`@okf-kernel capabilities/linter`) owns the
curation questions they raise[^upstream-spec] — including the two Migration
findings that name what a v0.1 bundle would change, without ever being able to
fail it.
