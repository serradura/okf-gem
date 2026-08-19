---
type: Overview
title: Lineage
description: What CODE and PARA supplied, what GTD supplied, what was deliberately left behind, and the three points where this design breaks with both its sources.
sources:
  - id: basb
    resource: https://www.buildingasecondbrain.com/
    title: Building a Second Brain
    author: Tiago Forte
  - id: gtd
    resource: https://gettingthingsdone.com/
    title: Getting Things Done
    author: David Allen
generated:
  by: human:maintainer
  at: 2026-08-17
---

# Nothing here is invented from nothing

Two established systems supply most of the machinery. A third pillar was added
because both share the same blind spot. Stating the debts precisely is not
courtesy: a borrowed rule carries the reasoning that justified it, and a rule
whose provenance is lost gets re-argued from scratch every time someone
questions it.

# Building a Second Brain — the Know and Work pillars

CODE (Capture, Organize, Distill, Express) treats knowledge as something that
moves, and its load-bearing insight is that **distillation is a separate act
from capture**.[^basb] Systems that collapse the two become archives nobody
rereads. PARA files by actionability rather than by topic — not *where does this
belong subject-wise*, a question with no stable answer, but *what is my
relationship to this right now*.[^basb]

**Taken:** capture as a distinct, near-frictionless step; distillation as its own
act, which is why `learnings/` exists at all; actionability as the filing axis;
and projects-drive-to-done against areas-maintain-a-standard — a distinction
[Law 3](/design/three-laws.md) later needed, because legitimate stillness in an
area is what keeps the dormancy alarm from crying wolf.

**Left:** Resources as one room, split three ways because it was three retrieval
questions. Archives as a *place* — it became a status, since moving files breaks
citations. And tool-agnostic vagueness: this design commits to plain files in a
validating format.

# Getting Things Done — the Work and State pillars

GTD's durable insight is psychological before it is organisational: an open loop
held in the head consumes attention whether or not you act on it, and the cure
is externalising into a system you actually trust.[^gtd] Trust is the operative
word — a system you half-believe is worse than none, because you keep a shadow
copy in your head anyway.

**Taken:** ubiquitous capture, and the claim that trust is the whole product;
next action, singular and physical, which is why the board holds one line per
demand and the full list stays in the project; waiting-for as its own class with
a chase date, because it is the category that rots silently; and a recurring
ritual as the thing that keeps state true, which here became the end-of-day
sitting.

**Left:** contexts (`@phone`, `@computer`), an artifact of a pre-mobile world.
The unbounded next-actions list — a list with no ceiling is precisely how
priority inflation sets in. Someday/maybe as a dumping ground, replaced by a
Backlog that is visible and counted. And the habit heuristics, which are
behaviour rather than structure.

# The Board — what neither source had

Both are blind to time. PARA says where a thing lives, CODE says how knowledge
matures, and neither says what today looks like or leaves a record of what
happened. GTD has lists but no memory: it faces relentlessly forward, and a done
item evaporates. Ask any of them what you worked on in March and what changed,
and there is no answer.

What the third pillar makes computable is set out in
[three-pillars](/design/three-pillars.md); the short version is that dormancy,
invisible labour, and Law 2's deltas all require a system that remembers its own
previous state.

# Where this design breaks with its sources

* **Both assume a human author.** Accountability could stay implicit when
  everything in the system was typed by the person who trusted it. Once an agent
  writes a hundred concepts an hour that guarantee is gone, and provenance has to
  become explicit — `generated:`, `verified:`, and the rule that an agent may
  summarise but may never conclude that what it summarised needs nothing.
* **Both treat structure as personal.** This design treats it as enforceable: a
  validating format, hooks that refuse, a pre-commit that audits, CI that blocks.
  Not rigour for its own sake — a system co-written with agents needs rules that
  are executable rather than remembered.
* **Neither confesses.** PARA never says *this folder may be incomplete*; a GTD
  list never says *I have not been reviewed in three weeks*. Law 2 is the
  genuinely new demand, and it is the one that most changes daily experience.

Law 1 is the other new requirement, and it belongs to the era rather than to the
sources: when writing is cheap and plentiful, the scarce discipline is
confronting what is already there.
