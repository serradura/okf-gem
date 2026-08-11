---
type: Constraint
title: The server trust boundary
description: The trust boundary for serving a bundle you may not fully trust — both XSS paths into the page are closed, the registry write routes carry their own locks, and every read is realpath-contained so a symlinked file cannot escape the bundle root.
resource: okf/lib/okf/render/graph/template.html.erb
tags: [security, server, xss, containment]
timestamp: 2026-08-10T12:00:00Z
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

# A third boundary: a file may not be where its name says

Everything above trusts that a file inside the bundle *is* inside the bundle. A
symlink breaks that: its name sits under the root, but its target need not, and
`File.expand_path` — the lexical guard every read used — resolves the name, not
the link. So a bundle carrying `services/billing.md → /etc/passwd`, or an
`index.md` symlinked outside the root, had its target read and served: verbatim
over the [graph server](../capabilities/graph-server.md) and `okf render`, and —
the reason it finally mattered — over [okf-mcp](../capabilities/mcp-server.md)'s
`--http`, to any host that could reach the port. Two code comments and a test
name asserted a containment that was never enforced; none tested it.

The guard is the target's real path now, not its name. Every read a bundle
serves — the Reader's bulk load, the single-concept handle, the live `log.md`
re-read, and the MCP concept and index reads — goes through one shell primitive
(`OKF::SafeRead`) that resolves `File.realpath`, refuses a result outside the
real root (`Path.under?` is the pure decision, the I/O stays in the shell), and
reads from the *resolved* path so a swap cannot slip between the check and the
open. An escaping file is quarantined like any unreadable one, so one planted
link cannot take a whole bundle down, and an escaping or vanished concept reads
as a plain not-found rather than an error naming the target.
<!-- rule:okf-realpath-contains-reads -->

The durable half is the rule the old comments claimed and did not hold: **a
lexical path check guards the name; a symlink escapes by its target, and only
`realpath` sees where a name actually leads.** The boundary is drawn where it
can be, not oversold past it — the same discipline the
[extension seam](extension-points.md) applies to its prefix: a hardlink shares
its target's inode and keeps an in-root path that `realpath` cannot distinguish,
and neither a hardlink nor a symlink survives a `git clone`, a copy or a tarball.
So the portable, adversarial bundle is a symlink's to plant and `realpath`'s to
close; the hardlink case is a local, non-portable one, named rather than claimed
covered, because the obvious guard (reject `st_nlink > 1`) would break a bundle
on a deduplicating filesystem.

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
[3] [okf/lib/okf/safe_read.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/safe_read.rb) — the one realpath-containment primitive every bundle read passes through; `Path.under?` in `okf/lib/okf/path.rb` is the pure decision it feeds.
