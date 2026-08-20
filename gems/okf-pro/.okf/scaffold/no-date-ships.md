---
type: Decision
title: No date ships in the generated bundle
description: A template is cloned an unknowable number of days after it is built, and every shipped date ages into somebody else's calendar.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The rule

No visible date anywhere in the generated tree: no log heading, no journal
entry, no `updated` line on the board. The empty-state paths are the design —
an undated `log.md` passes the audit, the session banner says `Last snapshot:
none yet`, dormancy stays quiet while the journal is empty, and the first dirty
day's stop gate hands over the computed snapshot line, which is the ritual
teaching itself.

# The failure that decided it

Dormancy measures a bundle's age by its **oldest journal entry**. A shipped
day-zero entry therefore makes a fresh clone read as an old bundle, and the
adopter's first promotion draws a dormancy question it never earned — on their
first day, from a gate they have no reason yet to trust.

The journal guard compounds it: a past day is append-only, so a foreign entry is
locked against correction forever.

None of this is a rule about tidiness. It falls out of the same question
[the ownership split](/scaffold/ownership-not-subject.md) answers: the bundle is
the adopter's from the moment it is written, and a date in it is a claim about
their days.

# The exemption, which is required rather than cosmetic

`projects/index.md` teaches the closure marker, and `Pairing::MARKER` **requires**
a date. The example cannot lose its date without teaching a spelling the gate
rejects, so dates inside code spans are exempt — and the exemption is what the
invariant test encodes, rather than a blanket ban it would then have to violate.

That coupling is pinned in both directions: every spelling the template and the
skill teach must be one `MARKER` accepts, and every counter-example the skill
names must be one it refuses. A spelling taught and rejected leaves the project
open and tells the person who followed instructions that they did it wrong.
