---
type: Constraint
title: The server trust boundary
description: The served page sanitizes each concept body before rendering and escapes inlined data, so both XSS paths into the page are closed.
resource: lib/okf/server/templates/graph.html.erb
tags: [security, server, xss]
timestamp: 2026-07-12T12:00:00Z
---

# Overview

The [graph server](../capabilities/graph-server.md) renders whatever bundle you
point it at, and a bundle is just files, so the page has to assume a body might
carry active content. Two defenses handle that — one for each path into the page.

# Where the boundary sits

There are two data paths into the page, and each carries its own guard:

| Path | Handling | Safe? |
|------|----------|-------|
| Graph data **inlined** into the page | through `json_for_script`, which escapes `<` | yes — it cannot break out of its `<script>` |
| Concept bodies **fetched** on demand (`/node?id=`) | `marked` renders the Markdown, then `DOMPurify.sanitize` scrubs it before it reaches the DOM | yes — scripts, handlers, and `javascript:` URLs are stripped |

The [description](../format/cross-links.md) shown in the inspector takes a third
path and never needs the client's help: the server escapes it
(`OKF::Server::App#description_fragment`) before sending it, so it arrives inert.

# What sanitizing does not cover

DOMPurify removes the code, not the content. The page still fetches and shows the
links, images, and Mermaid diagrams a body names (Mermaid runs in its `strict`
mode), and it pulls Cytoscape, marked, and DOMPurify from a CDN. So the rule is no
longer *only serve bundles you trust* — it is the ordinary care you would give any
document from a source you do not know.

# Citations

[1] [README.md — Server trust boundary](https://github.com/serradura/okf-gem/blob/main/README.md) — the two-defense summary.
[2] [lib/okf/server/templates/graph.html.erb](https://github.com/serradura/okf-gem/blob/main/lib/okf/server/templates/graph.html.erb) — `json_for_script` and the `DOMPurify.sanitize(marked.parse(...))` render.
