---
type: Decision
title: Three laws
description: Nothing is written without confronting what is already there; every view confesses its blind spots; attention is a budget, renegotiable but never silently exceeded.
---

# The laws

> **Law 1 — Writing is reconciliation.** Nothing enters the corpus without
> confronting what is already there.
>
> **Law 2 — Every view confesses its blind spots.** A view states what it
> cannot see with the same prominence as what it can.
>
> **Law 3 — Attention is budgeted, not requested.** Anything claiming attention
> draws from a finite, visible budget.

Every failure in [failure-modes](/design/failure-modes.md) traces to one of the
three, plus one thing no law closes ([the residue](/design/the-residue.md)).
They are behavioural rather than schema because the deaths they prevent are
attention leaks, and no frontmatter field has ever fixed one.

# Each law's admitted limit

The limit is the load-bearing half. A law stated without one invites the
confidence that makes it dangerous.

**Law 1 catches contradictions as well as your recall does, and no better.**
Vocabulary drift defeats it silently: two concepts that disagree in words you
did not think to search for never meet. So the law is a ratchet with two
checkpoints rather than a guarantee — search at ingestion, collision at read
time — and the consequence is that `index.md` (findability) and `glossary/`
(vocabulary) are this law's load-bearing organs, not hygiene.

**Law 2's confession must be a delta, not a status.** A permanent "47
untriaged" banner becomes wallpaper: a confession that is always present carries
zero information, and a check that always cries trains its reader to skip it —
at which point Law 2 has started violating Law 3. `inbox 14` says nothing;
`+8 inbox, oldest now 6d` says what the week did to you.

**Law 3's cap is renegotiable, never silently exceeded.** Eight critical things
against a cap of five is not a bug in the cap — it is overload made undeniable
on the day it happens, forced into a conversation instead of accumulating
privately. Raising the cap is the system working; a visible renegotiation is
journal-worthy. What is forbidden is pretending the table seats six.

# Where each law lives

* **Law 1** — `reconcile-search` fires on every new concept and returns the
  colliding vocabulary while the write is still hot. What cannot be settled on
  the spot becomes a dated conflict line on the board, where it competes under
  the cap: an unresolved contradiction is work.
* **Law 2** — the end-of-day snapshot line in `log.md`, read against yesterday's.
  The confession structurally cannot lie: the stop gate recomputes every counter
  and refuses a line that disagrees with the board it summarises, carrying the
  recomputed line in the refusal. A checker, never a generator — see Agent Drift
  in [failure-modes](/design/failure-modes.md).
* **Law 3** — the `In flight: k/CAP` header. Promotion requires demotion.
  Dormancy asks after `Budget::DORMANCY_DAYS` working days, quiet while the
  journal is younger than its own window, because a bundle in its first week is
  new rather than dormant. `roadmap.md` is the same budget at quarterly
  wavelength.

# Every number here is a guess until use tunes it

The cap of five, the five-working-day dormancy window, the seven-day deadline
lookahead, the staleness table: none is derived from anything. They are
visible-and-wrong by design — a number in a header that someone argues with is
worth more than a number nobody can see. When one proves wrong in use, the
change is a decision in the adopter's own `areas/corpus.md` first, then the
rule, then a log line.
