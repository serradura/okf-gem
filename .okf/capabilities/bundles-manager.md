---
type: Capability
title: Bundles list (the hub's /b/ page)
description: The hub's /b/ page — every bundle it knows about with its size, health and default marker — and the four POST routes that change the registry, which the graph page's Bundles panel drives.
resource: lib/okf/server/hub.rb
tags: [server, registry, hub, ui]
timestamp: 2026-07-21T00:00:00Z
---

# Why it exists

The [registry](../registry.md) has always been a terminal thing: `okf registry
set`, `del`, `default`, `rename`. That is the right surface for the people who
write the bundles, and the wrong one for the people who read them. A meeting with
non-technical readers settled it — the registry needed a point-and-click
surface, and the [server](graph-server.md) was already most of the way there.

The `/b/` page used to be a bare list of links. It became the browser
counterpart of the TUI's bundles view — every fact needed to choose between
bundles, and forms to change the set.

Then the [graph page](graph-server.md) grew a **Bundles panel** behind the rail's
⚙, and for a while both surfaces carried the same four verbs. Two
implementations of one contract is the thing that drifts, so the forms came out
of `/b/` and the routes stayed. The split that survives is a clean one: `/b/`
answers *which bundles are there*, from a page you can land on with no bundle
open at all, and the panel answers *change this one* where the reader already
is. Managing a set is something you do while reading it, not on a detour to a
page you had to know existed.

# What a row says

One row per bundle the server *knows about*, which is deliberately not the same
as one per bundle it *hosts*. A registry entry whose folder was deleted cannot be
served, and leaving it off the page answers "where did my bundle go?" with
silence; it shows, muted, with `folder is gone` and no link.

Each row carries the title, the `@slug` you would type at the CLI, the folder,
the concept count, and a **health verdict** — `ok`, `warn`, `error` — drawn as a
3px rule on the row's left edge. That rule is the accent bar under the page's own
heading, stood on end and put to work; colour only reinforces it, and the word
beside it is the message, so nothing on the page depends on being able to see
red. The verdict keeps the [validate/lint separation](validator.md): a curation
finding is a warning and the bundle stays open, and only a non-conformant bundle
reads as broken.

Rows are matched to entries by **directory**, not by slug. A rename changes the
slug and nothing else, and a row that lost its identity over a rename is the bug
that avoids.

# Writes, and the four locks on them

Four routes change anything — `POST /registry/default | rename | remove | add` —
and each passes four gates before it runs. They are the only non-GET routes the
server has:

1. **Is this server writable at all?** A loopback bind is, without a flag: the
   audience this page was built for should not need a command line to use the
   page they were pointed at, and `okf server --read-only` is how they decline it.
   Any other address is refused outright, with no flag that opens it: `--bind
   0.0.0.0` is how a personal tool becomes a public one, and a write surface does
   not follow it there at all. A read-only server offers no controls *and*
   refuses the request that skipped them — hiding a button is a UI, refusing the
   request is the boundary.
2. **Is there a registry to write to?** An ephemeral hub (`okf server ./a ./b`)
   is serving directories somebody typed and has no list to edit — `409`, and the
   page says so rather than leaving the missing controls a mystery.
3. **Is the verb one of the four?** The path is user input, and "call whatever
   method the path names" is how a router becomes an `eval`. A frozen list, not
   a lookup.
4. **Did this come from this page?** Same-origin *and* a per-boot token. Neither
   alone is enough: the token lives in a page, and a page is a thing another
   site can get a reader to submit; Origin alone would trust every
   tab the browser has open on this host. An unstated origin is refused rather
   than assumed. Per-boot rather than per-session because the hub has no sessions
   and wants none — a cookie jar is a subsystem to defend for a page four people
   see.

A success writes the file, **rebuilds the hub's bundles and apps from disk**, and
answers with the outcome. The rebuild is the part that is easy to skip and
impossible to skip safely: a write that leaves the running server on the old set
is a lie the next click believes.

Every answer is JSON, and Accept decides nothing. It used to be one of two
renderings — a `303` back to `/b/` for the forms, so a reload never re-posted,
and JSON for the panel's `fetch()`. With the forms gone there is one caller, so
there is one shape; asking for HTML does not resurrect a page-shaped answer that
nothing would read. The refusal messages are the core's own — a reserved slug, a
collision, a slug nothing carries all raise `OKF::Error` with a sentence written
for a person, and repeating that judgement in the server is how the two come to
disagree.

# The page carries no script, and nothing to post

No JavaScript, no build step, and now no forms and no token either: a page with
nothing to post has no business holding the credential. What is left is what only
this page can be — the list, the place `/` redirects from when no bundle is
named, the way back from the [404](graph-server.md), and the **empty state**. That
last one is why it cannot simply be deleted along with its forms: a hub with zero
bundles serves no graph page, so there is no page for the panel to live on, and
something still has to say what happened and how to fix it.

**There is no Add anywhere**, on either surface. A browser cannot hand over a
filesystem path — the File System Access API yields an opaque handle, never a
path, and is Chromium-only besides — and registering is the agent's act. The
route is still there because `okf registry set` is not the only caller that could
want it, but nothing in the UI reaches it.

# Verification

`test/integration/server/hub_writes_test.rb` is the critical layer: every verb's
happy path, every refusal, and each of the four gates, asserting both that the
registry file changed *and* that the live hub reflects it without a restart.
`test/browser/specs/bundles-panel.spec.js` drives the same verbs in Chromium
through the panel, against a registry-backed server with its own `$OKF_HOME` —
serial, and each spec puts back what it changed, because they share one live
registry.
<!-- rule:okf-prove-the-write-lands -->

A browser pass over these writes earned its place immediately, back when they
were forms: it caught an HTML `pattern` attribute whose character class was valid
as a Ruby regexp and invalid under the `v` flag a browser compiles it with, so
every keystroke in the rename field threw a `SyntaxError` no integration
assertion could see.

# Citations

[1] [lib/okf/server/hub.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/server/hub.rb) — the /b/ page, the four POST routes, the four gates, and the rebuild-after-write.
[2] [lib/okf/cli/server.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli/server.rb) — `--read-only` and the loopback rule that decides whether the hub is writable.
[3] [lib/okf/registry.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/registry.rb) — the CRUD the page drives, and the messages its refusals carry.
