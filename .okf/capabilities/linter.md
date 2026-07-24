---
type: Capability
title: Curation linter (lint)
description: An advisory curation-quality report across six categories and seventeen checks — it never rejects a bundle.
resource: okf/lib/okf/bundle/linter.rb
tags: [curation, cli]
timestamp: 2026-07-17T16:00:00Z
---

# Overview

`okf lint` answers the question [validate](validator.md) is forbidden to touch:
*is this bundle well-curated — navigable, complete, trustworthy?* It reports over
exactly the soft things §9 tolerates, has its own `OKF::Bundle::Linter` and
report, and never emits a conformance error. It is **advisory**: exit `0` even
with findings unless you opt in with `--fail-on warn`.

# Six categories, seventeen checks

| Category | Checks |
|----------|--------|
| Reachability | `orphan`, `not_in_index`, `disconnected_component`, `unlinked` |
| Backlog | `missing_concept`, `broken_index_entry` |
| Completeness | `stub`, `missing_title`, `missing_description`, `missing_timestamp` |
| Freshness | `stale` |
| Provenance | `uncited_external`, `broken_citation` |
| Hygiene | `duplicate_title`, `unused_reference_def`, `undefined_reference`, `self_link` |

Select with `--only` / `--except` (by check id), tune the stub threshold with
`--min-body`, and get the whole report as a machine substrate with `--json`.

# The freshness gotcha

Freshness is **off by default** — a plain `lint` never reports `stale`. Pass
`--stale-after <90d | 12w | 2026-01-01>` when concepts carry a
[`timestamp`](../format/frontmatter.md). The CLI resolves that to an absolute
cutoff so the pure linter never reads the clock.

# Where lint stops and an agent begins

`lint` is structural: it cannot judge **contradictions** or **semantic**
staleness (a concept that parses fine but no longer matches reality). Those need
meaning. `lint --json` is precisely the structured input an agent reasons over to
close that gap. The [`loose`](read-views.md) view is a folder-grouped lens over
the single `unlinked` check.

# Citations

[1] [okf/lib/okf/bundle/linter.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/bundle/linter.rb) — the seventeen checks and their categories.
