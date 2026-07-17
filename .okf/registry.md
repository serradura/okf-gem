---
type: Component
title: The bundle registry
description: A per-user, ordered list of bundle references persisted as one JSON file under $OKF_HOME — the kernel behind a bare `okf server`.
resource: lib/okf/registry.rb
tags: [cli, shell, registry]
timestamp: 2026-07-17T02:00:00Z
---

# Overview

`OKF::Registry` is the gem's only piece of *durable user state*: an ordered list
of bundle references, so `okf registry set` today and a bare `okf server`
tomorrow share one list. It is a plain JSON file — `$OKF_HOME/registry.json`,
`$OKF_HOME` defaulting to `~/.okf` — and that is a design choice, not a stopgap: a
database would break the [two-dependency rule](design/runtime-dependencies.md),
and the file is per-user, hand-editable, and greppable. It is part of the
[shell](design/core-shell-split.md); it reads and writes a file.

The registry stores *references*, never content. It holds a path, a slug, and a
title — the bundles themselves stay where they are on disk, owned by the repos
they document. Nothing is copied, so nothing can go stale except the path itself.

# Slugs: implicit is forgiving, explicit is strict

A slug is the bundle's mount key (`/b/<slug>/`) and its name in the
[switcher](capabilities/graph-server.md). Where it comes from decides what a
collision means:

| Source | On collision | Why |
|--------|--------------|-----|
| the directory basename (`registry set ./docs`) | silently suffixed — `docs-2`, `docs-3` | you never asked for a name; the gem picks a free one |
| an explicit `--as SLUG`, or `registry rename` | raises | you *did* ask for that name, so quietly serving a different one is a lie |

That asymmetry is the whole rule: **the gem may invent a name, but it may never
substitute one you chose.** Both paths run the same normalization the ephemeral
(unregistered) bundles use, so a directory mounts under the same slug whether it
was registered or passed straight to `okf server`.

The rule cuts one layer deeper, at the empty string. Minting a slug from a
basename must *produce* something, so `slugify` falls back to a placeholder when
nothing survives normalization. Looking one up must not: a lookup that inherits
that fallback makes `@***` resolve to whatever bundle happens to be slugged
`bundle` — the gem substituting a name you never chose, which is the one thing
the rule forbids. So `normalize` (no fallback) backs every lookup and every
explicit ask, and `slugify` (placeholder) backs only basename minting.

# The default is a choice with a fallback

`registry default <slug>` names the bundle a bare `okf server` opens at `/`. It
is *chosen* state, and the fallback keeps it honest: when nothing is chosen — or
when the chosen slug no longer exists — the first registered bundle takes over,
so `/` always resolves. Two edits carry the choice with them: a `rename` moves the
default to the new slug, and removing the default bundle clears the choice rather
than orphaning it.

Identity is the **path**, not the slug: re-registering a directory already in the
registry refreshes its title in place instead of adding a twin.

# It names bundles for the whole CLI, not just the server

The registry began as the server's boot list and grew into the
[CLI](cli.md)'s name-resolution layer: wherever a verb takes a `<bundle-dir>`,
`@slug` resolves through it and bare `@` picks the default — the same slugs the
hub mounts at `/b/<slug>/`, so the name you click is the name you type. That is
what turns registering from "tell the server" into "give this bundle a name":
[`search`](capabilities/search.md) crosses several of them in one query, and no
verb needs a path once the bundle has a slug.

# It tolerates a world that changes underneath it

A registry entry is a bet that a directory still exists, and the registry never
prunes on its own — deleting a bundle from disk must not silently rewrite a list
the user curated. Instead `listing` marks the entry `missing`, so
[`registry list`](cli.md) shows the gap and the user decides. Reads are equally
forgiving: the original bare-array file shape still parses (it simply carries no
default), while a *corrupt* file raises with the fix — "fix or delete the file" —
rather than starting from an empty list and silently dropping every bundle.

That message invites a hand-edit, which is why the shape is checked and not just
the syntax: valid JSON is not a valid registry, and an entry missing its `path`
must fail here, as a usage error naming the file, rather than surviving to crash
a `File.directory?` three frames away. The [CLI](cli.md) does its half by
loading through a guard, so a broken file reaches the user as an error from
whatever verb they ran — not a backtrace from a verb that never rescued one.

Writes go to a temp file and are promoted with `rename`, the same atomic
promotion the [bundle writer](capabilities/library-api.md) uses, so a booting
server never reads a torn file. Two racing writers stay last-writer-wins: this is
a per-user file, and locking would buy nothing worth the complexity.

# It costs an embedding app nothing

`require "okf"` does not load it. The registry is reached only from the
[CLI](cli.md), which requires it at the moment a registry verb or a bare `server`
runs — the same on-demand rule the [library API](capabilities/library-api.md)
keeps for the command-line machinery.

# Citations

[1] [lib/okf/registry.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/registry.rb) — the entries, the slug rules, the default fallback, and the atomic write.
