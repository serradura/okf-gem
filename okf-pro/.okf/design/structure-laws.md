---
type: Decision
title: Structure laws
description: The seven rules that decide whether a room, a field or a file may exist — a directory is a retrieval question, and state lives in exactly one place.
---

# The rules

* **A directory is a retrieval question; a type is ontology.** A room pays rent
  by answering a question no other room answers. This is why `reference/`,
  `learnings/` and `glossary/` are three rooms and not one: *what others
  produced*, *what I concluded* and *what a word means here* are three different
  questions asked at three different moments.
* **State lives in exactly one place.** Listings enumerate, never aggregate. The
  second copy agrees; the third one rots, and nobody can tell which is current.
* **Location is filing; lifecycle is metadata.** Nothing moves on a status
  change. Closure, deprecation and staleness are fields and markers, because a
  move breaks every citation pointing into the thing that moved, to buy a
  tidiness nobody asked for.
* **Capture is a line, not a file.** A staging folder is a blind spot by
  construction — things enter it and are never enumerated again. The attention
  claim and the artifact are separate objects, and only the first one is urgent.
* **A maintained view survives by being bounded.** Next-action-only is what
  makes hand maintenance honest: if it is bounded enough to maintain, it is
  bounded enough to read at a glance. A board carrying every step is a project
  plan wearing a board's clothes.
* **No new room until an incident forces it.** Rooms are cheap to add and
  expensive to retire, and an empty room still costs a decision every time
  something is filed.
* **Instructions are not knowledge.** A file is in the bundle because it answers
  a retrieval question. Rules, documentation and code live outside it, without
  frontmatter. This one was paid for: `README.md` and `CLAUDE.md` once carried
  `type:` for no reason but their address.

# Why they are stated as laws rather than preferences

Each one is a veto that can be applied to a proposal in the moment it is made,
by someone who was not there when the design was argued. "Where would this go?"
is a question with no stable answer; "what question does this room answer that
no other room does?" has exactly one, and it is usually *none*.

The rules also compose with the three behavioural laws
([three-laws](/design/three-laws.md)) rather than sitting beside them. Bounded
views are Law 3 applied to a page. One-place state is what lets Law 2's
confession be recomputed and checked. Capture-as-a-line is what keeps the
five-second cost that makes Law 1's ingestion checkpoint reachable at all.
