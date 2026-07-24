---
type: Component
title: The bundle registry
description: An ordered list of bundle references persisted as JSON — global under $OKF_HOME, or project-local via `okf registry init` and discovered from the working directory — the kernel behind a bare `okf server`.
resource: okf/lib/okf/registry.rb
tags: [cli, shell, registry]
timestamp: 2026-07-24T12:00:00Z
---

# Overview

`OKF::Registry` is the gem's only piece of *durable user state*: an ordered list
of bundle references, so `okf registry set` today and a bare `okf server`
tomorrow share one list. It is a plain JSON file — `$OKF_HOME/registry.json`,
`$OKF_HOME` defaulting to `~/.okf` — and that is a design choice, not a stopgap: a
database would break the [two-dependency rule](design/runtime-dependencies.md),
and the file is per-user, hand-editable, and greppable. It is part of the
[shell](design/core-shell-split.md); it reads and writes a file. That is the
*global* registry; a project can keep its own, discovered from the working
directory — see [Global by default, project-local by discovery](#global-by-default-project-local-by-discovery).

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

**The read normalizes for the same reason**, and it is the same bug one step
wider: two of the three ways in normalized and the third did not. A hand-typed
`"slug": "My Docs"` listed perfectly well while `@my-docs` missed it — and so did
`rename` and `default`, which look an entry up through the very normalization the
read had skipped. The two verbs that could repair the entry were the two that
could not see it. A slug registration would have handed back untouched is left
alone (including one already suffixed, so fixing a sick entry never renames a
healthy one); everything else is minted around what the other entries hold.
<!-- rule:okf-registry-read-normalizes -->

That asymmetry was also the [graph server](capabilities/graph-server.md)'s XSS
trigger: slugs reach the bundle switcher's HTML, and the only way one could carry
a quote was to arrive un-normalized through this read. Normalizing closes it at
the source — the escape is hardened too, because a page whose safety depends on a
guarantee three layers away is not one you can reason about locally.

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
[CLI](cli.md)'s name-resolution layer: wherever a verb takes a `<dir>`,
`@slug` resolves through it and bare `@` picks the default — the same slugs the
hub mounts at `/b/<slug>/`, so the name you click is the name you type. That is
what turns registering from "tell the server" into "give this bundle a name":
[`search`](capabilities/search.md) crosses several of them in one query, and no
verb needs a path once the bundle has a slug.

It is also no longer terminal-only. The graph page's ⚙ Bundles panel drives
`default`, `rename` and `remove` from a browser, through
[this class and its messages](capabilities/bundles-manager.md) rather than around
them. `add` stays terminal-only, because a browser cannot hand over a filesystem
path. The file stays the record: every write goes through here, and the hub
re-reads it per request rather than trusting a snapshot, so an `okf registry
rename` in another terminal shows on a refresh.

# Groups: a named set of bundles

A **group** is a slug that names not one bundle but a *list* of members — bundle
or group slugs, so groups nest — and resolves, recursively and path-deduped, to
the bundle leaves underneath. It is the durable form of typing `@a @b @c`: once
several bundles earn a name together (`okf registry group backend @orders
@billing`), `@backend` stands in for the set. `group`/`ungroup` add and remove
members; emptying a group deletes it, since an empty set resolves to nothing.

Groups live in **their own list** (`{ bundles: […], groups: […] }`), not among
the entries — a deliberate separation. The first-is-default rule and every
`File.directory?` guard assume an entry has a path, and a group has none;
threading a nil path through all of them to host a pathless member would be the
foreign-key tax the default rule already refused. A separate list leaves the
bundle invariants untouched and makes a group exactly what it is: a view over
them.

**One namespace, two kinds.** A slug names a bundle *or* a group, never both, so
`@backend` is unambiguous — the collision check that already spanned entries and
the reserved `all` now spans groups too, in both directions (`registry set --as
backend` is refused while a group holds it, and vice versa). And because a member
list stores slugs, the two lifecycle verbs keep those references live: `rename`
**cascades** the new name across every group that named the slug, and `del`
**cascade-drops** it (a group emptied that way is deleted). Skipping either would
orphan a member silently — the same drift the path-not-slug identity rule avoids
for the default.

**Only a set-taking verb consumes one.** [`search`](capabilities/search.md) and
[`server`](capabilities/graph-server.md) are the two verbs that already take
several bundles; a group feeds exactly them (`okf search @backend …` merges the
members into one ranking, `okf server @backend` mounts each). Every single-bundle
verb refuses a `@group` with exit 2 — the same second-bundle rule that stops
`okf lint a b` from linting `a` and ignoring `b`, because a group resolving to
three bundles is that ambiguity by another spelling. `@all` is unchanged: it
still names every registered *bundle*, and a group is a named subset of what it
already covers. A cycle is refused at write time and guarded again at resolution,
since the file is hand-editable.
<!-- rule:okf-registry-groups-cascade -->

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

# Global by default, project-local by discovery

The registry has two homes, and which one answers is decided by *where you stand*,
not by a flag. The global one is the `$OKF_HOME/registry.json` above — one per
user, shared across every repo. The project-local one is a `.okf-registry.json`
that `okf registry init` drops in a directory; okf finds it by walking up from the
working directory, and while you are inside its tree it **replaces** the global one
— every registry op, and every [`@slug`](cli.md), resolves through it. So a bare
`okf server` inside a repo serves that repo's bundles with no `$OKF_HOME` setup,
and a project carries its own named set without touching the user's global list.

**The file's presence is the whole state.** There is no stored "local mode", the
same way the [default is a position, not a stored name](#the-default-is-a-position-not-a-stored-name):
a mode flag would be one more thing to set, dangle, and reconcile, where the file
being *there* is self-evident and self-cleaning. The nearest one on the path up
wins, so nested registries resolve nearest-first, and `okf registry list` names the
file it found so which one is answering is never a guess.

`$OKF_HOME` still names *where the global registry lives*; it does **not** veto a
nearer local one. That direction is deliberate: `$OKF_HOME` is commonly exported
once and left, so letting it win would silently defeat the feature for exactly the
users who set up a project registry. The escape hatch is therefore a per-invocation
signal, not a second sticky variable — `OKF_NO_DISCOVERY=1`, set inline, forces the
global registry for a fixed-cwd caller (CI, a tool) that cannot just `cd` out.

# A project-local registry stores portable paths

The global registry stores absolute paths — correct for `~/.okf`, whose bundles
are scattered across the disk with no shared anchor. A committed project registry
needs the opposite: a bundle **inside** the registry's own tree is stored *relative*
to the `.okf-registry.json`, so the file travels with the repo — a checkout on
another machine, or a container mounting it, resolves the same bundles unchanged. A
bundle **outside** the tree keeps an absolute path, because a relative path that
climbs out cannot be re-anchored anywhere useful, and being honest that it will not
travel beats a `../../..` that breaks on the first move.

The relative form lives **only on disk**. A path resolves to absolute the moment it
is read, so `entry.path`, [`registry list`](cli.md), and the server mount all go on
seeing the absolute paths they always did — the portability is a property of the
file, invisible to every consumer. And because only the write side relativizes, an
existing absolute local entry migrates to relative on its next write: a registry
written before this existed heals itself the first time it changes.
<!-- rule:okf-registry-local-discovery -->

# It costs an embedding app nothing

`require "okf"` does not load it. The registry is reached only from the
[CLI](cli.md), which requires it at the moment a registry verb or a bare `server`
runs — the same on-demand rule the [library API](capabilities/library-api.md)
keeps for the command-line machinery.

# Citations

[1] [okf/lib/okf/registry.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/registry.rb) — the entries, the slug rules, the first-is-default rule, and the atomic write.
