---
type: Component
title: The Server and the Page
description: One ERB template that is the whole UI, served by a Rack app or baked to a file by `render` — plus the hub that mounts many bundles and owns the only writes in the server.
tags: [structure, server, rack, render, xss]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/render/graph.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/render/graph.rb` | the ERB render — `Graph.static` bakes a file, the same class serves the page |
| `lib/okf/server/app.rb` | the Rack app for one bundle: the page and its JSON endpoints |
| `lib/okf/server/hub.rb` | N bundles at `/b/<slug>/`, plus the routes only a set can answer |
| `lib/okf/server/hub/not_found.rb` | the 404 page: what was asked for, what exists, and the nearest match |
| `lib/okf/server/runner.rb` | the built-in WEBrick to Rack bridge — no rackup file needed |

The template itself is `graph/template.html.erb` beside `render/graph.rb`, and it
is ~1,300 lines of inline JS and CSS. Both halves open with a section map; the JS
one also names the three seams that actually couple the sections
(`applyGraphFilter`, `setView`, the lazy caches). Read it before editing —
`grep -n '── '` on the template prints the same list with live line numbers.

# One template, two modes

`Render::Graph.static` bakes a self-contained file with the payload embedded;
`Server::App` serves the same template and lets the browser `fetch()` bodies on
demand. **The two modes diverge exactly there** — baked `EMBED` versus fetched
endpoints — which is why every browser spec runs twice, once against each.

`LAYOUTS` is the five Cytoscape layouts; `MIN_SIZE`/`MAX_SIZE` the node scaling.

# The page stays self-contained, and two XSS defenses hold the line

Only Cytoscape, marked and DOMPurify load from a CDN at boot; Mermaid, Panzoom,
MiniSearch and the extra layout engines lazy-load on first use. No htmx, no
bundler, no build step.

Two defenses, and a new render path that skips either one reopens the hole:

* **`json_for_script`** escapes `<` so inlined data cannot break out of its
  `<script>` — `LT_ESCAPE` is that literal.
* **`DOMPurify.sanitize(marked.parse(...))`** runs on every fetched body before
  it reaches `innerHTML`.

# App: the endpoints

`/` is the page; `/node`, `/node/meta`, `/catalog`, `/tags`, `/types`, `/index`
and `/log` are the JSON it pulls. `SEARCH_ENGINE` is `:index` here — a server
*can* amortise the build, which is the opposite of the CLI's default — and
`warm_search` is where that build happens, at boot rather than on the first
query.

The bundles it serves are loaded through [the-disk-shell](/structure/the-disk-shell.md).

# Hub: many bundles, and the only writes

`Hub` mounts each bundle under `MOUNT` (`/b/<slug>/`) and adds the routes a set
can answer that one bundle cannot: `GET /search` across all of them, `GET /b/`
for the listing, and `POST /registry/{default,rename,remove,add}`.

**Those four writes are the only writes in the whole server**, they are off
unless `writable:`, and they are guarded: `authentic?` and `same_origin?` with a
`token`, because a page that can rename a bundle is a page a hostile site would
like to submit a form to.

`Hub::NotFound` is a real page rather than a status code — it names what was
asked for, lists what exists, and offers the nearest slug by edit distance. It
carries its own CSS, mark and script because the 404 must render when the
bundle it was asked for does not exist.
