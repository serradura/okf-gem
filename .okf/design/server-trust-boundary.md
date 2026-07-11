---
type: Constraint
title: The server trust boundary
description: The served page renders concept bodies without sanitization, so only serve bundles you trust.
resource: lib/okf/server/templates/graph.html.erb
tags: [security, server, xss]
timestamp: 2026-07-11T12:00:00Z
---

# Overview

The [graph server](../capabilities/graph-server.md) is designed for trusted
bundles. Its page renders each concept's Markdown body **without sanitization**
(marked, no sanitizer), so a hostile bundle could carry active content. The rule
is simple: **only serve bundles you trust.**

# Where the boundary sits

There are two different data paths into the page, and only one is escaped:

| Path | Handling | Safe? |
|------|----------|-------|
| Graph data **inlined** into the page | through `json_for_script`, which escapes `<` | yes — it cannot break out of its `<script>` |
| Concept bodies **fetched** on demand (`/node?id=`) | rendered as Markdown, unsanitized | no — this is the trust boundary |

So the XSS boundary is not the inlined data (that is handled); it is the
on-demand [body](../format/cross-links.md) render. The
[self-contained page](../capabilities/graph-server.md) keeps external assets down
to Cytoscape and marked from a CDN, but that does not make the rendered body
safe.

# Citations

[1] [README.md — Server trust boundary](https://github.com/serradura/okf-gem/blob/main/README.md) — the unsanitized-render warning.
[2] [lib/okf/server/templates/graph.html.erb](https://github.com/serradura/okf-gem/blob/main/lib/okf/server/templates/graph.html.erb) — `json_for_script` and the body render.
