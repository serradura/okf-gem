---
type: Capability
title: Curation linter (lint)
description: An advisory curation-quality report across eight categories and twenty-six checks — pinned severities, an explicit clock, and it never rejects a bundle.
resource: okf/lib/okf/bundle/linter.rb
tags: [curation, cli]
generated:
  by: human:maintainer
  at: 2026-08-14T12:00:00Z
sources:
  - title: okf/lib/okf/bundle/linter.rb
    resource: https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/bundle/linter.rb
---

# Overview

`okf lint` answers the question [validate](validator.md) is forbidden to touch:
*is this bundle well-curated — navigable, complete, trustworthy?* It reports over
exactly the soft things §11 tolerates, has its own `OKF::Bundle::Linter` and
report, and never emits a conformance error. It is **advisory**: exit `0` even
with findings unless you opt in with `--fail-on warn` (any warn) or
`--fail-on info` (any finding at all).

# Eight categories, twenty-six checks — with pinned severities

| Category | Checks |
|----------|--------|
| Reachability | `orphan`, `not_in_index`, `disconnected_component`, `unlinked` |
| Backlog | `missing_concept`, `broken_index_entry` |
| Completeness | `stub`, `missing_title`, `missing_description`, `missing_generated` |
| Freshness | `expired`, `stale` |
| Provenance | `uncited_external`, `broken_source`, `unattributed_claim`, `unused_source`, `unprefixed_actor` |
| Attestation | `incomplete_computation`, `broken_attestation_ref` |
| Migration | `legacy_timestamp`, `legacy_citations` |
| Hygiene | `duplicate_title`, `unused_reference_def`, `undefined_reference`, `self_link`, `log_order` |

`log_order` is the first log-side check: §9 describes the log as date-grouped
entries newest first — prose, not an RFC keyword, so disorder is curation
slack here, never a [validator](validator.md) error, and only shape-valid
headings are compared (a malformed date is already the validator's, reported
once). `unprefixed_actor` reads both §7 identity fields with one consequence
each: a bare `verified[].by` reads as machine-confirmed (the §5.3 misread the
tier system exists to prevent), while a bare `generated.by` feeds no tier and
costs the audit trail — nobody downstream can tell a person from a process.

**Severity is API.** Every id has a pinned level in one tested constant
(`Linter::SEVERITIES`): machine consumers gate repo edits and CI on `:warn`
and drop `:info`, so a severity change is a behavior change for them — a new
gateable state gets a flag (`--fail-on info`), never a severity promotion.
Two of the calls carry their argument in the code: `unattributed_claim` warns
while its join-twin `unused_source` informs (a dangling footnote misattributes
a claim; an uncited source is only slack), and `expired` informs because a
`stale_after` passes on the calendar, not on a change — a warn would fail a
`--fail-on warn` gate on a morning nobody chose. The Migration pair is info
for the same reason: §13 says a v0.1 bundle is consumable forever, and a
migration campaign gates explicitly with
`--only legacy_timestamp,legacy_citations --fail-on info`.

Select with `--only` / `--except` (by check id), tune the stub threshold with
`--min-body`, and get the whole report as a machine substrate with `--json` —
which also carries the bundle's posture: a `trust` tier distribution (in the
hyphenated wire spelling) and an effective-`status` frequency.

# The clock contract

The linter is pure and never reads a clock: `expired` runs only when the
caller supplies `today:` (the CLI passes today, or `--today YYYY-MM-DD` for a
reproducible report), and `stale` only when `--stale-after
<90d | 12w | 2026-01-01>` supplies a cutoff over `generated_at`. Every
clock-gated check that was selected but could not run is *named* in
`stats[:skipped_checks]` — a gate that is sometimes absent and does not
confess converts "unchecked" into "checked and fine". The flag and the
frontmatter field that share the `stale-after` spelling are different
mechanisms: the flag is the reader's age cutoff (`stale`), the field the
author's declared expiry (`expired`).

# Where lint stops and an agent begins

`lint` is structural: it cannot judge **contradictions** or **semantic**
staleness (a concept that parses fine but no longer matches reality). Those need
meaning. `lint --json` is precisely the structured input an agent reasons over to
close that gap. The [`loose`](read-views.md) view is a folder-grouped lens over
the single `unlinked` check.
