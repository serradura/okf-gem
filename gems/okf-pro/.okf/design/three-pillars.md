---
type: Overview
title: Three pillars
description: Know, Work and State — three questions no one of them can answer alone, and why the zones of the bundle are the pillars themselves.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The three questions

* **Know** — *what do I know?* `reference/` (what other people produced),
  `learnings/` (what I concluded), `glossary/` (what a word means here).
* **Work** — *what am I responsible for?* `projects/` drives to done, `areas/`
  maintains a standard indefinitely.
* **State** — *what am I doing, and what did I do?* `board.md` is the forward
  lens, `journal/` the backward one, and `log.md` remembers yesterday's numbers.

The zones are not a filing convenience laid over the pillars; they **are** the
pillars, which is why the tree has no room that answers to none of the three.
Everything around `.okf/` — instructions, hooks, workflows, this gem — is
enforcement or code, and none of it is knowledge.

# Why State is a pillar and not a view

Know and Work are borrowed and unoriginal, and deliberately so
([lineage](/design/lineage.md)). State is the addition, and it earns pillar
status rather than sitting as a rendering of the other two because three
capabilities exist only once a system remembers its own previous state:

* **dormancy** — an in-flight demand no journal entry has linked in five
  working days must re-justify its slot. The signal is derived from the
  temporal record; a pure filing system cannot compute it.
* **invisible labour becomes evidence** — a hallway decision produces no
  artifact, so the journal is its only proof at review time.
* **deltas** — the whole refinement of
  [Law 2](/design/three-laws.md) needs yesterday's numbers to compare against.

Ask a filing system what happened in March and it has nothing to say. That
silence is what the third pillar answers.

# Where two pillars touch

A capture is one dated line on the board — the claim on attention lands in
State while the artifact, if there ever is one, files into Know. The inbox line
is that seam, and it costs five seconds on purpose: capture that costs more
stops happening on exactly the days it matters most, which are the busy ones.

Splitting the two is also what keeps a staging folder out of the design. An
`inbox/` directory would be a blind spot by construction — see
[structure-laws](/design/structure-laws.md).
