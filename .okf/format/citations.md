---
type: Format
title: Citations (spec §8)
description: The provenance convention that ties empirical claims in a concept back to their sources.
resource: okf/lib/okf/markdown/citations.rb
tags: [provenance]
timestamp: 2026-07-17T16:00:00Z
---

# Overview

A `# Citations` heading holds the external sources backing claims in a concept's
body. `OKF::Markdown::Citations` extracts them. Provenance is what separates
trustworthy knowledge from folklore: any external or empirical claim — a latency
number, an approval, a quota — should trace to a source here.

# Why it matters to the tooling

Citations are the input to the [linter](../capabilities/linter.md)'s
**provenance** category, which flags two failure modes:

- **uncited external claims** — a concept that asserts an external fact but cites
  nothing;
- **broken citations** — a citation whose link no longer resolves.

Because the [validator](../capabilities/validator.md) is forbidden from rejecting
a bundle over provenance, these live entirely on the lint side — advisory signal
that a curator (or an agent) acts on, never a conformance failure.

# Citations

[1] [okf/lib/okf/markdown/citations.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/markdown/citations.rb) — citation extraction.
[2] [SPEC.md §8](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/skill/reference/SPEC.md) — the citations convention.
