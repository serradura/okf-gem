---
type: Component
title: The bundle registry
description: An ordered list of bundle references persisted as JSON — global under $OKF_HOME, or project-local via `okf registry init` and discovered from the working directory, composable through links to other registry files and able to import rows out of them — the kernel behind a bare `okf server`.
resource: gems/okf/lib/okf/registry.rb
tags: [cli, shell, registry]
generated:
  by: human:maintainer
  at: 2026-07-24T12:00:00Z
sources:
  - title: gems/okf/lib/okf/registry.rb
    resource: https://github.com/serradura/okf/blob/main/gems/okf/lib/okf/registry.rb
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
user, shared across every repo. The project-local one is a `.okf.json`
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

That file was called `.okf-registry.json` first, and both names are still
discovered — a local registry is *committed*, so retiring the old one outright
would break every repository carrying it to save eight characters. The two are
checked **per directory** on the way up, not one name swept to the root and then
the other: otherwise a legacy file at a repo's root would beat a `.okf.json` two
levels down, and "the nearest one wins" would quietly mean something else. Inside
one directory the short name wins.

The deprecation is said **once, by the `registry` umbrella, and nowhere else**.
That verb is the one whose subject *is* a registry file and the one nobody runs in
a loop or pipes into something, which is exactly what `lint` and `search` are — a
note there is noise people learn to redirect away rather than act on. A legacy
file that is in force gets the one move that retires it; a legacy file sitting
beside the `.okf.json` that beat it gets named too, because reading one while the
other lies there unread is a silent wrong answer unless somebody says so.

`-g`/`--global` is that same signal spelled as an argument, and it is the
`registry` umbrella's alone (see [the CLI](cli.md#one-lever-not-two)). It exists
because a lever reachable only through an env var is a lever most users never
find — and the umbrella is the one verb whose *subject* is a registry file, so
naming which file to act on is an argument to it rather than a flag bolted onto
fourteen unrelated verbs. `init` is the exception that proves it: its whole job is
to create a *local* file, so `-g` there names nothing and is refused.

# A project-local registry stores portable paths

The global registry stores absolute paths — correct for `~/.okf`, whose bundles
are scattered across the disk with no shared anchor. A committed project registry
needs the opposite: a bundle **inside** the registry's own tree is stored *relative*
to the `.okf.json`, so the file travels with the repo — a checkout on
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

# Links: the global registry composes other registry files

A **link** is a pointer from the global registry to another registry file. That
file's bundles resolve through the pointer at read time, under their own slugs,
and nothing is copied — the same "stores references, never content" rule the
entries keep, one level up. `okf registry link onm ~/ONM/registry.json` and
`@onm-central` (or whatever slugs that file holds) answer here; the link name
itself resolves as a group over exactly its bundles, so `@onm` is the set.

The case it exists for is **a repository that already curates its own bundles**.
This repo commits a `.okf.json` naming five; before links, using them
from `~/.okf` meant registering all five again by hand and re-syncing whenever
the repo's list changed. A link points at the file the repo already maintains, so
the curation is composed rather than duplicated, and it keeps resolving its own
relative paths because the target is anchored on its own directory — exactly as
it would from inside that checkout. Two registry files stop being two worlds you
switch `$OKF_HOME` between and become one view.

**Only the global registry follows links.** A project-local one parses them and
preserves them across a write, but never resolves them — and that single
restriction is the whole depth rule. A linked file's own links are not read, so
no chain forms, no prefix compounds, and there is no cycle to detect. The
alternative was transitive resolution, and it fails on ownership rather than on
effort: the target is a file this registry does not own, so a cycle-check at
write time goes stale the moment someone adds a link back on the other side.
Transitivity would move cycle detection from write time — cheap, one file,
refusable — to read time, across N files, with nobody to blame. The groups above
nest safely for exactly the reason links do not: every member lives in one file,
behind one guard.
<!-- rule:okf-registry-links-global-only -->

# A linked name is minted around a collision, never refused

A slug arriving from a linked file answers to itself when the name is free, and
to `<link>-<slug>` when it is not (`-2` beyond that, through the same `dedupe` a
basename goes through). That is the [implicit is forgiving, explicit is
strict](#slugs-implicit-is-forgiving-explicit-is-strict) table one row wider, and
the row falls on the forgiving side for the reason the table gives: a name in
someone else's file was never *chosen* here, so inventing around it is licensed —
while refusing would let one foreign row take down an entire link. The link
*name* is the strict half, and is refused on collision like any `--as`: you typed
that one.

Precedence is fixed so the derivation is reproducible: the registry's own bundles
always win the bare name, and between links the file's order decides. Both are
position, which is state the registry already keeps — the same reason the
[default](#the-default-is-a-position-not-a-stored-name) is one.

What this costs, and it is the design's one genuinely computed name: a slug can
*move* when an unrelated link is added. Everything else in this file is stable in
the file. The mitigation is disclosure rather than a mechanism — `registry link`
says what it moved as it writes, and `registry list` prints the moved row with the
slug it carries in its source file (`onm-central … [central]`), which is the only
place a shifted ref is visible. Linked entries also append **after** the local
ones, so while this registry owns any bundle at all the default stays local.

**A linked group is listed with the rest, not beside them.** `groups_listing`
returns this registry's own groups first, then the linked ones, each carrying the
`link` it came from — one list, because `group?` *resolves* a linked group and a
listing that named only the local half would answer about a smaller set than the
same object can resolve. That gap is invisible at the call site and inherited by
every consumer: `okf-mcp`'s `list_bundles` and the TUI's groups view both read
this one method, and both would have hidden a group they could already open. A
caller that wants only the groups it may edit filters on `link` — which is the
question they are actually asking, and it is now askable.

# A link is read-only, and the refusal lives in the model

`rename`, `del`, `default`, `set --as` and `group` all refuse a slug a link owns,
with a message naming the file that does own it and the `unlink` that would drop
it. Two of those are worth their own line. A **group** may not hold a linked slug:
a group stores names, and a linked name lives only while its link resolves, so
holding one would dangle the group the moment the link goes — the foreign key the
default rule already refused. And **`registry set` on a directory a link already
carries** is refused rather than quietly adding a twin, because entries are
identified by path and the path is already spoken for.

The third was a hole this rule had left open, and it failed in the worst
available way. A group's slug is its *update* path everywhere else — `registry
group backend @more` adds to the existing one — so `group onm @alpha`, naming a
link or a group that came with one, took that path: it merged the member, printed
`grouped onm → …`, and lost it, because `write` persists only the groups this
registry owns. A refusal is the fix, but the shape is what matters: a write that
reports success and does not happen is worse than one that raises, and it was
reachable from the CLI, the TUI and the browser panel alike.

The refusals live in this class, not in the [CLI](cli.md), and that placement is
load-bearing: the graph page's ⚙ Bundles panel posts into these same methods
([bundles manager](capabilities/bundles-manager.md)), so a guard one layer up
would leave the browser doing what the terminal refuses. A link whose target has
gone or cannot be parsed is *reported* — `(missing)`, `(unreadable)` — and
resolves to nothing, the same tolerance a vanished bundle directory gets, because
one dead pointer must not take down the registry that holds it.

# Import: the copy that owns what it takes

`okf registry import <@slug…>` copies chosen bundles — and the groups that hold
them — out of another registry file into the one in force. It is the **opposite
trade** from a link, and the pair is the point:

| | link | import |
| --- | --- | --- |
| what moves | nothing; a pointer | the reference, copied |
| scope | the whole target file | the slugs you name |
| ownership | the target keeps it, read-only | yours, editable |
| freshness | live on every read | a snapshot |

Copying a *reference* is not copying content, so the rule at the top of this file
still holds: the bundle stays in the repository that owns it, and what lands here
is the same path-and-name row `registry set` would have written. What import saves
is the laundering. The scenario is standing inside a repo, running `okf registry
list -g` to see what the global registry holds, and wanting one of them here — the
path is already on screen, and without this verb the only way to move it is
through the clipboard.

The source is `--from`, defaulting to the global registry, which inside a repo is
the only other one you have. It is a second flag rather than a second meaning for
`-g` because [`-g` names the registry acted *on*](cli.md#one-lever-not-two) on
every other subcommand; this verb names two files, so the second gets its own
name rather than inverting the first.

**A collision refuses.** This is where import and link disagree, and the
disagreement is the slug rule, not an inconsistency: a linked name was never
chosen here, so it is [minted around](#a-linked-name-is-minted-around-a-collision-never-refused);
an imported name lands in *this* file because you typed it, so it is refused
exactly as `rename` refuses. The gem may invent a name it made up; it may not
substitute one you chose. A bundle already registered here under a different name
refuses too, and *first* — when both are true, "that bundle is already here as
@docs" is the answer and "the name is taken" is only the symptom.

**A group brings everything it reaches**, including a group nested inside it.
Recreating a name here that resolved to a larger set there would be that same
quiet substitution, with nothing on screen to reveal it. Members are stored
verbatim, which is the payoff of preserving slugs: a name means the same thing on
both sides, so there is nothing to remap — the work `fold_linked_bundles` must do
precisely because a link mints its names.

**Nothing is applied until everything is checked.** Every ask is resolved and
refused against the current state first, then one `write` publishes the lot. Half
an import is a registry the user has to unpick by hand, reported as a success —
and a refusal that already moved three of four rows is not a refusal.
<!-- rule:okf-registry-import-all-or-nothing -->

# It costs an embedding app nothing

`require "okf"` does not load it. The registry is reached only from the
[CLI](cli.md), which requires it at the moment a registry verb or a bare `server`
runs — the same on-demand rule the [library API](capabilities/library-api.md)
keeps for the command-line machinery.
