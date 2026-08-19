---
type: Format
title: Cross-links (spec §6)
description: Plain Markdown links between concepts that become the knowledge graph's directed edges.
resource: gems/okf/lib/okf/markdown/links.rb
tags: [graph, diagram]
generated:
  by: human:maintainer
  at: 2026-08-13T12:00:00Z
sources:
  - title: gems/okf/lib/okf/markdown/links.rb
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/lib/okf/markdown/links.rb
  - title: SPEC.md §6
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/lib/okf/skill/reference/SPEC.md
---

# Overview

A cross-link is an ordinary Markdown link from one concept's body to another
concept file. `OKF::Markdown::Links` extracts them, and that is the whole edge
mechanism: the graph (`@okf-kernel model/graph`) is *emergent* — you never declare it,
it arises from the links you write. Good linking is good knowledge modelling.

```mermaid
flowchart LR
  orders["orders.md"] -->|prose link| customers["customers.md"]
  orders -->|prose link| refunds["refunds.md"]
  refunds -->|prose link| customers
```

Files are the nodes; the Markdown links in their bodies are the directed edges.
Nobody declared this graph — it fell out of three files linking each other.

# Untyped on purpose

A Markdown link asserts only "these two relate." The *kind* of relationship —
depends-on, supersedes, derived-from — lives in the **prose around the link**,
never in a made-up typed-edge syntax. Both a human and an agent already
understand a Markdown link, which is the point of the dual audience (`@okf-kernel overview`).

# What counts as an edge

- **Bundle-relative links** (e.g. `/model/graph.md`) resolve to another concept
  and become a directed edge. Absolute bundle-relative targets are preferred so
  links survive file moves.
- **External links** — `http(s)://`, `mailto:` — are surfaced separately and are
  *not* graph edges.
- A link to a concept that does not exist yet is **not an error** (§6.1): it is
  not-yet-written knowledge, which consumers MUST tolerate and the
  linter (`@okf-kernel capabilities/linter`) surfaces as backlog demand.

The graph server (`@okf-kernel capabilities/graph-server`) draws these edges; a
degree-0 concept (no links in or out) is a *loose* file the
read views (`@okf-kernel capabilities/read-views`) flag.
