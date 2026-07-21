---
type: Capability
title: Workspace manager (the hub's /b/ page)
description: The browser counterpart of `okf registry` — every hosted bundle with its size, health and default marker, and, on a loopback server, the forms that add, rename, remove and re-default them.
resource: lib/okf/server/hub.rb
tags: [server, registry, hub, ui]
timestamp: 2026-07-21T00:00:00Z
---

# Why it exists

The [registry](../registry.md) has always been a terminal thing: `okf registry
set`, `del`, `default`, `rename`. That is the right surface for the people who
write the bundles, and the wrong one for the people who read them. A meeting with
non-technical readers settled it — the workspace needed a point-and-click
surface, and the [server](graph-server.md) was already most of the way there.

The `/b/` page used to be a bare list of links. It is now the browser
counterpart of the TUI's bundles view: every fact needed to choose between
bundles, and — where the server is allowed to — the controls to change the set.

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

# Writes, and the three locks on them

The server was GET-only until this page grew forms. Four routes change anything
— `POST /registry/default | rename | remove | add` — and each passes three gates
before it runs:

1. **Is this server writable at all?** A loopback bind is, without a flag: the
   audience this page was built for should not need a command line to use the
   page they were pointed at. Any other address takes `okf server --allow-edit`,
   because `--bind 0.0.0.0` is how a personal tool becomes a public one and a
   write surface must not follow it there by accident. A read-only server renders
   the page with no forms *and* refuses the request that skipped them.
2. **Is there a registry to write to?** An ephemeral hub (`okf server ./a ./b`)
   is serving directories somebody typed and has no list to edit — `409`, and the
   page says so rather than leaving the missing controls a mystery.
3. **Did this come from this page?** Same-origin *and* a per-boot token in every
   form. Neither alone is enough: the token lives in a page, and a page is a
   thing another site can get a reader to submit; Origin alone would trust every
   tab the browser has open on this host. An unstated origin is refused rather
   than assumed. Per-boot rather than per-session because the hub has no sessions
   and wants none — a cookie jar is a subsystem to defend for a page four people
   see.

A success writes the file, **rebuilds the hub's bundles and apps from disk**, and
redirects (POST/redirect/GET, so a reload never re-posts). The rebuild is the
part that is easy to skip and impossible to skip safely: a write that leaves the
running server on the old set is a lie the next click believes.

A refusal does *not* redirect. It re-renders the manager with the reason on it,
because the message is the whole point of refusing and this audience cannot read
a status code. The messages are the core's own — a reserved slug, a collision, a
slug nothing carries all raise `OKF::Error` with a sentence written for a person,
and repeating that judgement in the server is how the two come to disagree.

# The page carries no script

Plain forms, no JavaScript, no build step — a document that needs a script to
remove a row is a worse document. Rename and Remove hide inside `<details>`,
which is the browser's own disclosure: one needs a field, the other needs a
confirmation, and a bare Remove button beside a name is a click nobody meant to
make. The disclosure opens *over* the page rather than through the row, so
opening one never moves the others.

**Adding is typing a path**, and that is not a shortcut taken. A browser cannot
hand over a filesystem path: the File System Access API yields an opaque handle,
never a path, and it is Chromium-only besides. So the field takes an absolute
path, and the server says exactly what is wrong with what was typed — not a
directory, no concepts in it, already registered under another slug.

# Verification

`test/integration/server/hub_writes_test.rb` is the critical layer: every verb's
happy path, every refusal, and each of the three gates, asserting both that the
registry file changed *and* that the live hub reflects it without a restart.
`test/browser/specs/workspace.spec.js` drives the forms in Chromium against a
registry-backed server with its own `$OKF_HOME` — serial, and each spec puts back
what it changed, because they share one live registry.
<!-- rule:okf-prove-the-write-lands -->

That browser pass earned its place immediately: it caught an HTML `pattern`
attribute whose character class was valid as a Ruby regexp and invalid under the
`v` flag a browser compiles it with, so every keystroke in the rename field threw
a `SyntaxError` no integration assertion could see.

# Citations

[1] [lib/okf/server/hub.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/server/hub.rb) — the manager page, the four POST routes, the three gates, and the rebuild-after-write.
[2] [lib/okf/cli/server.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli/server.rb) — `--allow-edit` and the loopback rule that decides whether the hub is writable.
[3] [lib/okf/registry.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/registry.rb) — the CRUD the page drives, and the messages its refusals carry.
