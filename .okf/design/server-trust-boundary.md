---
type: Constraint
title: The server trust boundary
description: The page sanitizes each concept body before rendering and escapes inlined data, so both XSS paths into the page are closed — served live or rendered static.
resource: okf/lib/okf/render/graph/template.html.erb
tags: [security, server, xss]
timestamp: 2026-07-18T17:00:00Z
---

# Overview

The [graph server](../capabilities/graph-server.md) renders whatever bundle you
point it at, and a bundle is just files, so the page has to assume a body might
carry active content. Two defenses handle that — one for each path into the page.

# Where the boundary sits

There are two data paths into the page, and each carries its own guard:

| Path                                               | Handling                                                                                     | Safe?                                                        |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Graph data **inlined** into the page               | through `json_for_script`, which escapes `<`                                                 | yes — it cannot break out of its `<script>`                  |
| Concept bodies **fetched** on demand (`/node?id=`) | `marked` renders the Markdown, then `DOMPurify.sanitize` scrubs it before it reaches the DOM | yes — scripts, handlers, and `javascript:` URLs are stripped |

The [description](../format/cross-links.md) shown in the inspector takes a third
path and never needs the client's help: the server escapes it
(`OKF::Server::App#description_fragment`) before sending it, so it arrives inert.

# The static render carries both guards

[`okf render`](../capabilities/render.md) bakes every body into the page
instead of fetching it, so an embedded body takes the *inlined* path **and** the
rendered one: `json_for_script` escapes it at inject time (a `</script>` inside a
body cannot break out of its `<script>`), and it is still
`DOMPurify.sanitize(marked.parse(...))`'d when the getter hands it to the DOM. The
same two defenses, now both on the one path — a static file is no laxer than the
server, and the embedded description stays server-escaped exactly as above.

# Both guards are asserted, against a bundle that attacks them

`okf/test/browser/specs/sanitization.spec.js` drives
`okf/test/browser/fixtures/hostile` — a conformant OKF bundle whose content is
trying to execute script in the page rendering it — in both render modes. The
payloads set flags on `window`, so the assertion is not "the markup looks
clean" but *the script did not run*.
<!-- rule:okf-verify-the-sanitizer -->

This was a gap the browser suite's coverage review turned up: for a long time
the only checks were that the string `DOMPurify` appeared in the emitted page
and that it was a function at boot, both of which a render path skipping the
sanitizer passes cleanly. The table above described intent, not a contract.

Each guard was then mutation-checked, because a security test that cannot fail
is worse than none:

| Mutation | Result |
|---|---|
| `DOMPurify.sanitize(marked.parse(…))` → `marked.parse(…)` | 4 body specs red; `__xssImg` **fired** — real code execution |
| `esc()` back to `&<>` only (pre-c2cedb6) | the tag breakout spec red; a live `onmouseover` in the DOM |
| `json_for_script` without its `<` escape | all 14 red — the `</script>` in a title closes the block and the page never boots |

The first of those carries a lesson for anyone extending the fixture: with the
sanitizer removed, the `<script>` payload did **not** fire, because `innerHTML`
does not execute script tags. Only the `<img onerror>` did. A fixture carrying
script tags alone would have gone green against a page with no sanitizer at
all — proving the defense while the hole stood open.

# A second boundary: the server can now be asked to change something

Everything above is about content coming *in* to the page. The
[registry routes](../capabilities/bundles-manager.md) opened the other
direction — four `POST` routes that write the [registry](../registry.md) — and it
carries its own three locks rather than borrowing these: writable-at-all (loopback
by default, declined with `--read-only`, refused outright anywhere else), a registry to write to, and same-origin
plus a per-boot token. Sanitizing has nothing to say about a well-formed request
that should not have been honoured, which is why that gate is described where it
lives instead of being folded in here.

# What sanitizing does not cover

DOMPurify removes the code, not the content. The page still fetches and shows the
links, images, and Mermaid diagrams a body names (Mermaid runs in its `strict`
mode), and it runs third-party code from a CDN — Cytoscape, marked and DOMPurify
at boot, with Mermaid, Panzoom, the extra layout engines and
[MiniSearch](../capabilities/graph-server.md) lazily on first use. Each of those
is trust extended to the CDN as much as to the bundle; MiniSearch alone is pinned
to an exact version (`7.2.0`), because it has to *agree* with the Ruby port rather
than merely work. So the rule is no longer _only serve bundles you trust_ — it is
the ordinary care you would give any document from a source you do not know.

# Citations

[1] [README.md — Server trust boundary](https://github.com/serradura/okf-gem/blob/main/README.md) — the two-defense summary.
[2] [okf/lib/okf/render/graph/template.html.erb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/render/graph/template.html.erb) — the inlined `EMBED` and the `DOMPurify.sanitize(marked.parse(...))` render; `json_for_script` (its `<`-escape) is the method in the sibling `render/graph.rb`.
