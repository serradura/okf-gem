---
type: Constraint
title: Where knowledge lives
description: A README, an AGENTS.md and a bundle answer three different questions for three different readers, so the same fact belongs in exactly one of them — and drift between two copies is what the split exists to prevent.
tags: [documentation, governance, boundary, bundles]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: AGENTS.md
    resource: https://github.com/serradura/okf-gem/blob/main/AGENTS.md
---

# Three readers, three files

| file | reader | answers |
|---|---|---|
| `README.md` | someone deciding whether to care | what this is, what it buys them, the shortest path to a working bundle |
| `AGENTS.md` | someone about to change the code | the contract a change may not break, the commands, and *where to read the rest* |
| `.okf/` | someone about to change the code, *before* they open `lib/` | what the code is, what it already answers, and why each rule is a rule |

A boundary gets its own README when a stranger can land on it directly — from a
search result, a package page, a pasted link. That is true of each gem and of
the CI recipe; it is not true of a container directory, because nobody arrives
at a container, they arrive at what it holds.

The root README is the **menu**: the ecosystem, one row per door, and no manual
for any of them. A front door that is also a manual for one item on it is a door
a visitor has to read past.

There are two `AGENTS.md` layers, not one. The root's is the ecosystem's: the
layout, the shared obligations, and one row per gem. Each gem's is that gem's:
its floor, its dependency limits, its own contract. A gem's file names the
root's as the general rule and itself as the instance, and the root names no
gem's contract at all — the same one-way pointer the bundles use.

# The rule underneath

**The same fact may be in one of them, not two.** Two copies of a catalogue do
not stay equal, and a reader who finds them disagreeing learns to trust neither
— which is worse than having only one, wherever it is.

This is why each gem's `AGENTS.md` stopped restating the shape of its own
`lib/`, and why this bundle carries no second copy of what `@okf` says
about okf. It is also why an `AGENTS.md` **routes rather than restates**: where
a concept already carries an argument, the guide keeps the one or two sentences
a reviewer checks against and links to the concept for the rest. A rule stated
twice is not twice as clear — the copies drift, and this is not hypothetical.
`okf-tui`'s guide once ended with a `Working style` section it had copied from
the root's while declaring in its own opening that the root owned that rule;
eight of its fourteen lines had silently diverged, and nothing on either page
said the other existed.

And it is why the split had to be by *kind* rather than by subject: what the
code **is** lives beside the code, where a test can hold it to the tree; what it
**means** lives where the argument belongs.

# The half a test holds

Structural documentation is code-derived, which makes it the kind that rots
silently: a file arrives, moves or leaves and a hand-written map keeps reading
plausibly. So every gem's `structure/` area is pinned by its own
`bundle_catalog_test.rb` — a file under `lib/` that no concept names, a concept
naming a file that is gone, or a catalogue out of step with the constant it
mirrors is a **red suite**, not a stale document.

The prose half cannot be pinned that way and is not pretended to be. It is held
by [a different rule](nothing-runs-it.md): say plainly which obligations nothing
enforces.
