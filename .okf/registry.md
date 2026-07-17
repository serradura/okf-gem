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
was registered or passed straight to `okf server` — with exactly one exception,
the reserved `all/` below, which the registry alone has a reason to rename.

The rule extends cleanly to a name the grammar has already spoken for. `@all`
means *every registered bundle* to [`search`](capabilities/search.md), so no one
bundle may answer to `all` — it is reserved. A directory named `all/` therefore
registers as `all-2` (the basename was only a guess, so a suffix is right), while
`--as all` is refused (the ask was deliberate, so substituting `all-2` would be
the lie).

The reservation is the *registry's*, not the slug helper's, and that boundary is
load-bearing in both directions. Inward, all three ways a slug enters this list
are covered — minting, an explicit ask, and **reading the file**. The third is the
one that cannot refuse. `all` reaches the file two ways nothing can take back: a
release from before the name was reserved wrote it (a directory named `all/`
slugged exactly that), or a hand typed it into the file the format invites you to
edit. So the read *mints around it* — the entry lists, mounts, and answers to
`all-2`, and the next write persists the name.

Refusing the file was the first answer here, and it was worth the correction it
took. A name the grammar has taken makes **one entry** unnameable; rejecting the
registry makes **every** entry unreachable — and takes `del` and `rename`, the two
verbs that could fix it, down on the very read they need to survive, leaving
hand-editing JSON as the only way out. A guard whose failure mode is worse than
what it guards against is not a guard. Minting is also simply the rule already
stated above, read one line further: the gem may invent a name, and here the name
on disk cannot be used, so inventing one is the only move that is not a lie.
<!-- rule:okf-registry-reserved-mint -->

Outward, it stops there: an ephemeral `okf server ./all` has no
registry and no refs, so there is no name to protect, and it mounts at `/b/all/` —
suffixing it would invent a `/b/all-2/` whose `/b/all/` does not exist. `all/` is
therefore the one directory whose registered slug and ephemeral slug differ, and
they differ because only one of the two worlds has a grammar that spells `all`.

The rule cuts one layer deeper, at the empty string. Minting a slug from a
basename must *produce* something, so `slugify` falls back to a placeholder when
nothing survives normalization. Looking one up must not: a lookup that inherits
that fallback makes `@***` resolve to whatever bundle happens to be slugged
`bundle` — the gem substituting a name you never chose, which is the one thing
the rule forbids. So `normalize` (no fallback) backs every lookup and every
explicit ask, and `slugify` (placeholder) backs only basename minting.

# The default is a position, not a stored name

The first entry still on disk is the bundle a bare `okf server` opens at `/`, and
`registry default <slug>` moves that entry to the front. That is the whole
feature.

"Still on disk" is the one qualifier position needs, and it is not a fallback in
disguise. The hub drops a bundle whose directory has vanished rather than serving
a hole, so a default that ignored the gap would put `registry list`'s `*` on a
bundle `/` never opens — the star names what `/` opens, so it has to skip what `/`
skips. The rule stays derivable from the file plus the disk, with nothing stored
and nothing to reconcile. Its mirror is that `registry default <slug>` *refuses* a
vanished directory, exactly as `registry set` refuses to register one: both are
explicit asks, and a move the default would then skip would answer with a slug the
user did not type.

The alternative — storing the chosen slug — looks simpler and is not. A stored
slug is a *foreign key* into the same list it lives in, and a foreign key demands
referential integrity from every operation that touches the list: carry it
through a `rename`, re-point it when `add --as` renames in place, clear it on a
`remove`, and fall back when it dangles anyway. Four obligations, each a place to
forget. Position owes nothing: a rename touches the name and leaves the row where
it is, a `del` lets the next row become first, and a default that is not in the
list is *unrepresentable* rather than merely handled. The registry was already
documented as ordered, so this is state it kept for free.

What it costs is a file that visibly reorders, which is why `registry default`
says so in its own help — the JSON is meant to be read and hand-edited, and a
reordering write should never be a surprise.

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
forgiving: the original bare-array file shape still parses, while a *corrupt*
file raises with the fix — "fix or delete the file" —
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

[1] [lib/okf/registry.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/registry.rb) — the entries, the slug rules, the first-is-default rule, and the atomic write.
