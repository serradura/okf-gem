---
type: Component
title: OKF::Concept
description: The pure in-memory model of a single OKF file — frontmatter, body, and a stable id.
resource: gems/okf/lib/okf/concept.rb
tags: [pure]
generated:
  by: human:maintainer
  at: 2026-08-14T12:00:00Z
sources:
  - title: gems/okf/lib/okf/concept.rb
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/lib/okf/concept.rb
---

# Overview

`OKF::Concept` is the atomic node: a `path`, a parsed
`frontmatter` (`@okf format/frontmatter`) hash, and a Markdown `body`. It is
[pure](../design/core-shell-split.md) — it holds no file handle and does no I/O.
The on-disk counterpart is `OKF::Concept::File`, part of the
[library API](../capabilities/library-api.md).

# The id is the concept's identity

`#id` is the concept's **stable identifier** across the whole system — the graph
node key, the link target, and the thing you name a concept for. By default it is
the `path` minus `.md` (e.g. `model/graph.md` → `model/graph`), which is why you
name a file for what it *is*, not where it sits. A frontmatter `id`, when set,
pins the identity explicitly — the path-derived name is the fallback, not the only
source — so a concept can keep its id across a move.

The override is this gem's **extension, not spec**: §2 defines the concept id
as the path minus `.md`, full stop. Pinning one puts the concept in two worlds
on purpose — the identity views ([catalog, hubs, `--dir`,
search](../capabilities/read-views.md)) follow the id, because the edges do,
while the physical views (`index`, `dirs`, stats' `by_dir`) keep the file where
it lives, because an index is a physical listing. An integration test holds a
concept whose id leaves its directory and asserts both worlds at once, so the
split stays a decision; the authoring advice is the default's — rename the
file, not the id.

# What it derives from its own content

The concept parses its body on demand into the structural facts the rest of the
gem consumes:

- `#type`, `#title`, `#description`, `#resource`, `#tags` — typed reads over
  the frontmatter;
- the §5 families, each carrying §13.1's fallbacks inline: `#generated` /
  `#generated_at` / `#generated_by` (a legacy `timestamp` lifts into `at`,
  per-key, with no actor ever invented), `#sources` (the native list, or the
  legacy `# Citations` (`@okf format/citations`) body list whenever the native
  value yields zero mappings), `#verified` (a bare mapping reads as a
  one-element list; degenerate shapes fold to unverified), `#trust_tier` /
  `#trust` (derived per §5.3, never stored), `#status`/`#declared_status`
  (absent reads stable; both keep the producer's spelling, because every
  surface that *displays* a status prints what was written — the fold belongs
  to `.effective_status`, which is what narrowing compares through), `#stale_after_date`/`#stale_on?(today)` (§5.5 — stale
  on the day itself; the clock is always an argument, never read);
- the §10 contract of an Attested Computation: `#runtime`, `#parameters`,
  `#computation`, `#executor`, `#attester`, `#attested_computation?`;
- `#usage_window` — validated for shape, deliberately consumed by nothing: no
  gem surface computes over usage counts, so an effective-window resolver
  would be speculative;
- `#declared_generated?`, `#legacy_timestamp?`, `#legacy_citations?` — raw-key
  detection for lint and the surfaces; detection never influences reading;
- `#links` — every raw cross-link (`@okf format/cross-links`) target in the body, in order; the bundle-relative ones become graph edges;
- `#external_links` — the subset of those that are URLs or `mailto:` (not edges);
- `#to_markdown` — the inverse of the frontmatter parser (`#citations` is gone,
  subsumed by `#sources`);
- `#lint` — the concept-scoped [lint](../capabilities/linter.md) checks in isolation.

A concept never decides conformance alone; a [bundle](bundle.md) does, because
some checks (duplicate titles, missing link targets) are only meaningful across
the set.
