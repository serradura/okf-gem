---
type: Decision
title: It Writes the Registry, Never a Bundle
description: The line the TUI's side effects sit on is not read-versus-write — it is the registry versus the knowledge; what that admits, what it excludes, and why `registry init` is on the far side of it.
tags: [registry, boundary, side-effects]
timestamp: 2026-08-13
---

# Overview

The TUI has side effects, and more of them than a reader expects from something
described as a viewer. It registers bundles, removes them, renames slugs, moves
the default. The question that keeps coming up — *should it also create groups?
rename them? do everything the CLI does?* — cannot be answered by asking whether
a feature writes to disk, because the answer is already yes.

The line is **the registry, not read-versus-write**: this program edits the user's
*configuration* freely and never touches the *knowledge*.

# What that admits

Seven of okf's eight `registry` verbs have a place here, and it is the same place —
the bundles view, where `Workspace` owns every write and each is followed by a
reload, per `AGENTS.md` constraint 8:

| Key | `Workspace` | okf CLI |
|-----|-------------|---------|
| `a` | `add` | `okf registry set <dir>` |
| `x` | `remove` | `okf registry del <@slug>` — spans a group |
| `d` | `make_default` | `okf registry default <@slug>` |
| `n` | `rename` | `okf registry rename <@slug> <new>` — spans a group |
| `c` | `create_group` | `okf registry group <slug> <@member…>` |
| `+` | `add_to_group` | `okf registry group <slug> <@member…>` |
| `-` | `remove_from_group` | `okf registry ungroup <slug> <@member…>` |
| — | the view itself | `okf registry list` |

Group create/edit was the question that forced this file to be written, and it
falls on the admitted side: a group is registry configuration in exactly the sense
a slug rename is. Stopping at read-only would have put a `@mkt` row on a screen
where `x` already deletes a bundle, and refused to let you add a member to it —
not restraint, just an arbitrary stopping point.

**The members come from the scope, not from a typed list.** `◉` already means
"these bundles" in this view, so the gesture is toggle what you want and then name
it (`c`), or put the cursor on a group and push the scope into it (`+`) or out of
it (`-`). That is a gesture the CLI cannot offer, and it is why these keys are
worth having rather than being a second spelling of `okf registry group`.

okf owns every cascade. `set_group` creates-or-adds and refuses a cycle,
`unset_group_members` deletes a group it empties, and `rename`/`del` span a group
slug and cascade through every member list that names it. None of that is
reimplemented; `groups_test.rb` asserts the *effects* — that renaming `@docs`
leaves `@everything` naming `@papers` — precisely so the cascades stay okf's.

# What it excludes

Nothing in `lib/` writes a bundle. There is no `OKF::Bundle::Writer` reference in
this gem, and that is the invariant worth grepping for: no concept editing, no
"fix this lint warning for me", no touching a `log.md`. Authoring is okf's CLI and
its companion skill, which have the vocabulary and the review path for it.

The reason is not timidity. A registry is small, local, reversible and *about the
session* — a list of references, which is why removing a bundle famously does not
delete it. A bundle is the knowledge itself, and a full-screen keyboard UI is a
poor place to make an irreversible edit to it by muscle memory.

# `registry init` is excluded, for a different reason

okf 1.12.0 added `okf registry init`, which creates a project-local
`.okf-registry.json`. It is registry configuration, so the line above admits it —
and it is still not offered, on mechanics rather than principle.

The registry is resolved **once, at boot**: `Workspace#load_entries` opens it, and
every reload after that goes through `Registry#reopen` on the same file. Creating
a *new* registry mid-session is not an edit to the thing the session is on, it is
a **re-anchoring** — after it, the file every other okf verb in that directory
would now resolve is one this session has never read. Either the key appears to do
nothing, or the entire workspace silently swaps out from under every open view,
including the active bundle the other five views are about.

Both outcomes are worse than not having the key. The CLI is the right door, and
once the file exists the TUI discovers it on the next launch — which is
`Workspace.new(cwd:)`, and the fix recorded in
[which-registry](/interaction/which-registry.md).

# The removal key, got wrong twice

The first cut put removal on `-` at the group row, acting on the bundles the scope
and the member list had in common. It shipped, and the report came back at once:
someone looking for how to *turn the scope off* pressed `-`, and it deleted a group.

Three things lined up, and the missing confirmation was only one of them:

- **`-` reads as "remove", and the nearest removable thing was the scope.** Where
  `◉` means "a search covers this", a key marked `-` is a scope key until proven
  otherwise.
- **The footer had dropped the scope keys on a group row** and labelled the member
  keys `+/- add/remove scoped` — so the one screen someone stands on while wanting
  to stop searching everything offered no `A`/`N`, and did offer a `-` described
  with the word *scoped*. Close to an instruction.
- **okf deletes a group whose last member leaves.** Right for a CLI where the
  command names its members explicitly; here it meant one keystroke could destroy
  the group rather than trim it.

Adding a confirmation fixed the damage and left the real fault in place, which the
next round of feedback named: `-` acted on **`scope ∩ members`, a set with no row
on screen**. To predict the key you had to intersect two lists in your head, and
the review comment was simply "it took me some time to understand how this works".

The fix that stuck was structural, and it came from the maintainer rather than from
me: **give the groups a pane of their own.** The bundles view is three panes now —
bundles, groups, and the detail of whichever has focus — with `Tab` cycling.

That does more than tidy the layout. Two panes hold *two selections at once*, and
suddenly every editing key has visible rows to name: `+` is the bundle under the
bundles cursor joining the group selected below, `-` is the member under the members
cursor. Nothing reads the search scope any more except `c`, where naming the bundles
you have been searching together is precisely the gesture. The key I had got wrong
twice stopped being hard the moment the layout gave it something to point at.

It also fixed a fault nobody had reported yet: the groups were a heading inside the
bundle list, and a heading scrolls away. Thirteen registered bundles put them below
the fold on a short terminal — no way to show a thing you are meant to select. A
pane is always on screen, and `Tab` is the jump to it.

Three rules came out of it, in increasing order of how far they carry:

1. A write that can lose configuration confirms, and the question names the
   outcome — `remove @nested — its last, so @docs goes too`, not a bare "remove?".
2. **Act on a row, not on a set the reader has to compute.** A key whose effect is
   an intersection of two lists cannot be predicted from the screen, and every
   misreading of it is reasonable.
3. **A hint must not borrow the vocabulary of a different mechanism.** Two
   independent axes live in this view — the active bundle and the scope
   ([cross-bundle-scope](/interaction/cross-bundle-scope.md)) — so a registry write
   described in the scope's words will be read as the scope's key.

Reuse also mattered: `Tab` already meant "switch pane" in browse and graph, so three
panes cost a reader nothing new, and `Esc` peels them one at a time before the
filter, exactly as
[esc-peels-one-layer](/interaction/esc-peels-one-layer.md) requires. A key that
belongs to a different pane *says where it lives* rather than going silent — a key
that quietly stopped working is indistinguishable from a broken one.

The last thing, and the smallest, was the one the report actually opened with:
"it is not clear how to control the scope." It was not. Neither `A` nor `N` appeared
in the footer on a bundle row, and the footer truncates, so at 80 columns everything
past `d` was already off screen. The scope is one of this view's two axes
([cross-bundle-scope](/interaction/cross-bundle-scope.md)); it belongs in the
visible prefix, ahead of the config keys, and that is where it is now.

# The test that keeps it honest

Every write test builds its own registry: `with_registry` under a temporary
`$OKF_HOME`, and `with_local_registry` for the project-local file. Nothing in the
suite may touch the real `~/.okf` — it is the maintainer's own configuration, and
this is a suite that exercises `remove`.

Two states in `groups_test.rb` are reached by writing the registry JSON directly,
because okf's own API refuses to produce them: a member naming nothing registered,
and a cycle (`group cycle: @g would contain itself`). Both are legitimate things
to survive, since okf invites you to *commit* a local registry — so a hand-edited
file is a normal input, not an abuse.

# Citations

[1] `lib/okf/tui/workspace.rb` — the seven writes, each returning a status message
    and reloading; `not_registry_backed` for the ad-hoc case, which has no registry
    to change.
[2] `AGENTS.md` constraint 8 — the same boundary, stated where a change is judged.
[3] `grep -rn "Bundle::Writer" lib/` → no matches, 2026-08-13.
[4] okf `CHANGELOG.md` 1.12.0 — `okf registry init`, and the discovery rule that
    makes the nearest `.okf-registry.json` win.
[5] `test/test_helper.rb` — `with_registry`, `with_local_registry`, and the
    `$OKF_HOME` save/restore around both.
