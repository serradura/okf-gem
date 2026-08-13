---
type: Format
title: Sources (spec §5.1)
description: The provenance family that ties empirical claims in a concept back to their sources, and the legacy body list it replaced.
resource: okf/lib/okf/markdown/citations.rb
tags: [provenance]
generated:
  by: human:maintainer
  at: 2026-07-17T16:00:00Z
sources:
  - title: okf/lib/okf/markdown/citations.rb
    resource: https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/markdown/citations.rb
  - title: SPEC.md §5.1
    resource: https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/skill/reference/SPEC.md
---

# Overview

A `sources:` frontmatter list records what a concept derives from (§5.1): each
entry carries at least a `resource`, optionally an `id` the body cites with a
`[^id]` footnote, a `title`, and the credibility signals `author`,
`usage_count`, `last_modified`. Provenance is what separates trustworthy
knowledge from folklore: any external or empirical claim — a latency number, an
approval, a quota — should trace to a source here.

"Citation" is the legacy spelling (v0.2 §2 retires the term): v0.1 kept
provenance in a body `# Citations` list, and §13.1 keeps that list readable
forever — [`Concept#sources`](../model/concept.md) lifts it into the same
mappings whenever the native key yields nothing, through
`OKF::Markdown::Citations`, which is v0.2 reading code, not a leftover.

# Why it matters to the tooling

Sources are the input to the [linter](../capabilities/linter.md)'s
**provenance** category, which checks the keyed-attribution join in both
directions (`unattributed_claim` warns — a dangling footnote misattributes a
claim; `unused_source` informs — recorded but never cited is only slack),
flags external links with no sources at all (`uncited_external`), and verifies
in-bundle source targets (`broken_source` — URLs and scope descriptors are
exempt by construction). An in-bundle `sources[].resource` is also a graph
edge, so recording provenance is also linking (§5.1's lineage).

Because the [validator](../capabilities/validator.md) is forbidden from
rejecting a bundle over provenance, it warns only about *shape* (a list of
mappings, `resource` REQUIRED within an entry); everything judgment-shaped
lives on the lint side — advisory signal a curator acts on, never a
conformance failure.
