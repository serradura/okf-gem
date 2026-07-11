---
type: Component
title: OKF::Bundle::Graph
description: The in-memory knowledge graph — concepts as nodes, cross-links as directed edges, with type and tag indexes.
resource: lib/okf/bundle/graph.rb
tags: [model, graph, pure]
timestamp: 2026-07-11T12:00:00Z
---

# Overview

`OKF::Bundle::Graph` turns a [bundle](bundle.md) into nodes and edges:
[concepts](concept.md) become nodes keyed by id, and bundle-relative
[cross-links](../format/cross-links.md) become directed edges. It is pure — it
carries no presentation concerns; sizing and colour belong to a renderer like
the [graph server](../capabilities/graph-server.md).

# Fidelity is a build option

The same graph ships at three weights, so a client downloads only what it needs
and fetches the rest on demand:

| Build | Node payload |
|-------|--------------|
| default (`body: true`) | id, type, title, description, tags, **body** |
| `body: false` | everything but the body |
| `minimal: true` | just id and title — the leanest payload to draw |

# Indexes come free at every weight

Regardless of node fidelity, the graph exposes two inverted indexes computed from
every concept:

- `type_index` — `{ type => [id, …] }`, so even a minimal client can colour nodes
  by [`type`](concept.md);
- `tag_index` — `{ tag => [id, …] }`, so it can filter by tag.

Those indexes, plus `unlinked_ids` (degree-0 nodes), are what the
[read views](../capabilities/read-views.md) — `tags`, `stats`, `loose` — are
built from.

# Citations

[1] [lib/okf/bundle/graph.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/graph.rb) — graph construction and the type/tag indexes.
