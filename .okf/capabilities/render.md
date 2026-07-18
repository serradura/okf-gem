---
type: Capability
title: Static render (render)
description: One self-contained HTML file with the whole graph baked in — the same page `okf server` serves, written to disk so it hosts where nothing runs (`okf render`).
resource: lib/okf/render/graph.rb
tags: [server, graph]
timestamp: 2026-07-18T10:00:00Z
---

# Overview

`okf render` writes the [graph page](graph-server.md) as one static,
self-contained HTML file with the whole bundle baked in — the *same* page
[`okf server`](graph-server.md) serves live, one switch apart — so the graph
hosts anywhere there is no server to answer a `fetch()`. GitHub Pages is the
motivating case: commit the file and the graph is browsable with no process
running behind it.

# One template, two modes

There is no second renderer to keep in sync with the server, because there is no
second renderer. One `OKF::Render::Graph` — the view paired with the pure
[graph model](../model/graph.md) — draws the page for both modes, and `okf render`
bakes the bundle in through its `.static`/`.payload`. Every data read the page
makes — a body, a description, the
catalog, the §6 map, the §7 logs — flows through a small set of getter functions,
and an injected `EMBED` constant chooses their source: `null` when served, so the
getters `fetch()` the live endpoints; the whole payload when rendered, so they
resolve from the page itself. One interface, two adapters, and the views never
know which is behind them. The [bundle switcher](graph-server.md) obeys the same
discipline in reverse — a static file injects an empty sibling list, so the
affordance that could only dead-end never appears.

# It carries both XSS guards

Baking the bodies in does not lower the page's defenses. An embedded body takes
the *inlined* path and the *rendered* one at once: `json_for_script` escapes it at
inject time so a `</script>` inside a body cannot break out of its `<script>`, and
it is still run through `DOMPurify.sanitize(marked.parse(...))` before the getter
hands it to the DOM. The [same trust boundary](../design/server-trust-boundary.md)
the live server keeps, carried onto the one static path — a rendered file is no
laxer than the server it was baked from.

# Output, flags, and the price

`okf render <dir>` prints the page to stdout — `okf render ./docs > public/index.html` —
or writes `-o FILE` directly, reporting the concept count when it does. A `-o`
path it cannot write is a usage error (exit `2`), not a backtrace — the same
[best-effort contract](../cli.md) the read views keep. `--layout NAME` bakes in a
graph layout, and `-t`/`-l` set the title and the link the page unfurls as a
preview card, since a static file cannot be told them later. The price is weight:
every body is inlined, where a live [`okf server`](graph-server.md) ships a minimal
graph and pulls bodies on demand — so the server stays the choice for a bundle too
large to ship whole, and the static file carries no compression of its own
(whatever host serves it compresses instead).

# Citations

[1] [lib/okf/cli.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli.rb) — the `render` verb: stdout vs `-o FILE`, `--layout`/`-t`/`-l`, and the exit-2 on an unwritable path.
[2] [lib/okf/render/graph.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/render/graph.rb) — `OKF::Render::Graph.static` and `.payload`, which bake the bundle into the template's `EMBED` payload.
