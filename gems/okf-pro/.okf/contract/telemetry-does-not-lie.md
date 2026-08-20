---
type: Learning
title: The third clause, applied to something that is not a check
description: The friction recorder neither refuses nor blocks, and still may not report a zero it did not count — because a measurement that quietly degrades to "nothing happened" retires itself.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# What it is

`Friction` records the moments an agent did by hand something an `okf pro` verb
could have done: a markdown write inside the bundle arriving through Bash, and
an Edit or Write whose target is `board.md` — that one path and no other, for
the reason *The prescribed path is not friction* gives below. It is the only
thing in this gem that is neither a gate nor a report: it exists so that
*"which verb is missing?"* is answered by evidence rather than by the
maintainer's imagination.

Two design constraints shaped it, and neither is about telemetry:

* **No new hook event.** `.claude/settings.json` is a *seeded* file
  ([scaffold/ownership-not-subject](/scaffold/ownership-not-subject.md)), so a
  new hook registration never reaches an adopter through `okf pro upgrade`.
  Friction rides code paths that are already wired, or it does not ship.
* **It records intent, not outcome.** `shell-guard` fires at PreToolUse, before
  the owner may deny. That is the right event anyway: the question is what was
  *attempted* by hand.

# The clause, and why it applies here

> No check ever fails silent.

This is not a check. It refuses nothing and blocks nothing, and a recorder that
crashed a gate would be a measurement worth less than the thing it measures — so
every failure path in it is rescued and swallowed. That is the correct trade in
one direction and a trap in the other: the natural consequence of swallowing a
failed write is a log that stays empty, a report that says **0**, and a reader
who concludes the verbs are working.

A count of zero and *"the recorder could not write"* are different states, and
the whole value of the measurement dies the day they are confused. So:

* a failed write leaves a **marker** beside the log, and
* an unwritable scratch directory reaches the same verdict on its own — asked
  directly, because the case where the marker cannot be written either is
  exactly the case that proves a marker alone is not enough, and
* a recorded line that will not parse is **counted and confessed**, never
  dropped, because a corrupted log must not read as a quieter session.

`okf pro friction` and the session banner both say *unknown, not zero* when any
of that holds. Same shape as [silent-skips](/contract/silent-skips.md): the
failure was never the missing datum, it was the report that did not mention it
was missing.

# The prescribed path is not friction

The obvious list of files to watch is board, log, journal day — and it is
wrong, in the direction that destroys the measurement. `snapshot` deliberately
has no `--write` (a writer and a checker sharing a code path agree trivially),
so appending the Snapshot line to `log.md` by hand is *exactly what this gem
tells you to do*. `journal open` says in as many words that the day's content
is yours. Recording either counts the system working as evidence that it is
not: it inflates the banner's request and points the maintainer at verbs that
already exist and already declined that job.

So the Edit door records `board.md` and nothing else. That is the same rule
`own_command?` keeps one layer down — **the good path must not count as
friction** — applied to a path the code prescribes rather than to a command the
code owns.

That narrowing is also how this page went into the tree **wrong, in the same
commit as the code it describes**. Its opening paragraph read "board.md,
`log.md` or a journal day" — the list from before the argument above was made —
and a concept describing behaviour the code does not have is
[a-comment-is-not-an-implementation](/design/a-comment-is-not-an-implementation.md)
at one remove, with a wider readership. The narrowing left `classify`'s other
two answers unreachable from the edit door and its unit test still green, which
is the shape [fixture-is-a-client](/testing/fixture-is-a-client.md) records: a
test calling the function directly proves a branch no user can walk to. One
covered path means the class a row records **is** that path, so the function is
gone and the call site passes the path.

The shell door is different and stays broad, because a shell write is a bypass
whatever it touched: the trust guards read a tool event and a redirect produces
none. Which is why the report is keyed on the DOOR as well as the file. An Edit
to the board says a verb went unused; a shell redirect at the board says the
guards were bypassed, and what covers those is not the same answer.

**And the banner asks the narrower of the two questions.** `okf pro friction`
reports every row, because a maintainer reading it wants both. The session line
asks for a *verb*, so it may only count rows a verb would answer — and it
counted shell rows too, telling the adopter that a verb could have done
something no verb covers. Worse: `shell-guard` records intent at PreToolUse, so
the system working exactly as designed — guard fires, owner denies, agent uses
Edit — still incremented a lifetime counter that then nagged every session until
`--clear`. A measurement that fires when nothing went wrong is the
[a-rule-you-can-walk-past](/design/a-rule-you-can-walk-past.md) failure wearing
telemetry's uniform.

# Sticky, with a way out

The `.unavailable` marker is never cleared automatically, and that is correct:
one failed write means the count is short by an unknown amount from then on,
and a recorder that quietly forgave itself would be back to reporting a zero it
did not count.

Sticky with no way out is a different failure. A momentarily full disk pins the
answer at *unknown* forever, the banner nags about a week nobody can change,
and "check that `.tmp/` is writable" is not actionable once the directory is
perfectly writable and the marker is what is holding the verdict. So the way
out is explicit, named in the message, and the reader's: `okf pro friction
--clear`. It touches `.tmp/` and nothing else.

The same reasoning fixes the banner's arithmetic. The log is append-only and
nothing prunes it, so the count is a **lifetime total** and the line says so —
"so far", never "last session". A standing warning nobody can act on is the
failure [a-rule-you-can-walk-past](/design/a-rule-you-can-walk-past.md)
describes, and naming the reset is what keeps this one a request rather than
wallpaper.

# Where it points, and what it never does

The banner's friction line addresses the **adopter**, not the maintainer — they
are the ones paying for a missing verb and the only ones who can say which one
it is — and `okf pro friction --issue` prints a ready `gh issue create` against
this gem's repository. **Printed, never run.** Filing an issue is outward-facing
and irreversible, and a hook that did it unattended would be both without anyone
asking. If `gh` is absent it prints the URL and the body to paste.

**Nor does it draft a report about nothing.** `--issue` with an empty log
printed a complete, ready-to-paste issue whose body was an empty list and whose
title said *0 bundle edit(s)*. Nothing stopped an adopter sending it, and it
asked the maintainer to act on a measurement that had measured nothing. So a
count that is genuinely zero prints no issue at all.

Two states are not that, and both still file. *Unknown* is one — "the recorder
could not write" is something that happened. So is a log whose every line was
unparseable: zero rows with a positive `unreadable` count is a **corrupted**
recorder, not a quiet one, and reading the two as the same would have retired
the report in precisely the case it was most worth sending.

Which then has to hold on **every** surface, and briefly did not: `--issue`
declined to file for a quiet log and filed for a corrupted one, while the human
default and the session banner both called a corrupted log "nothing recorded"
and said nothing at all. A report is only as honest as its least honest surface,
and the default is the one most people read.

The same page, one more time: the issue BODY branched its whole content on
`available` and printed only "the recorder could not write, so the counts above
are unknown" — over a body with nothing above it, under a title that still
counted the rows. The marker is sticky by design, so one failed write weeks ago
made every later report evidence-free. A degraded recorder suppresses the
*claim to completeness*, never the evidence: the rows print, and the caveat says
the total is a floor.

The same rule caught the issue *title*. It read "N bundle edit(s) done by hand
that a verb could cover" over a body whose only row said `covered by: Edit or
Write` — the title is what a maintainer triages on, and it was asking for a verb
this gem had just decided not to want. It now says what was counted and claims
nothing about what covers it; the per-row note answers that.

One exclusion keeps the measurement honest: a command matching `okf pro` is not
recorded. Without it the good path counts as evidence against itself — `okf pro
snapshot >> .okf/log.md` *is* the prescribed way to add the Snapshot line.

But that exclusion is about a **write**, so two questions had to be separated,
and getting either wrong breaks the measurement in a different direction.

*Which command wrote?* Asked of the whole string, a mention anywhere suppressed
the record: `okf pro state && cat notes.md > .okf/board.md` prompted the owner
and counted nothing — and an agent chaining a read with a write is the commonest
shape there is, so the under-count sat exactly where the measurement mattered.
So the question is asked per command: a segment carrying no mutator is nobody's
write (`cd repo && okf pro promote alpha` is still this gem's), and a mutator in
a segment this gem does not own is a hand-write whatever else the line says. A
**pipeline is one command**, not two — splitting on `|` put this gem's own
redirect target in a segment of its own and recorded `okf pro snapshot | tee -a
.okf/log.md`, the prescribed move, as friction.

A pipeline being one command is right and is not a licence: `okf pro board |
sed s/a/b/ > .okf/board.md` starts with this gem and ends by regenerating the
board, which is failure mode 07 by name. Nothing prescribes piping into a path a
verb covers — `snapshot` appends to `log.md`, which no verb covers — so an own
command aimed at `board.md` is friction whatever produced the bytes.

*Is this an invocation, or a mention?* Anchored to the start of a segment, not
matched anywhere in it. Board lines routinely name these verbs, so a hand-append
whose CONTENT said `okf pro` excused itself: `echo "- see okf pro docs" >>
.okf/board.md` was never counted. An assignment prefix is skipped rather than
breaking the anchor — `$OKF_HOME` is a variable this ecosystem uses, so
`OKF_HOME=/tmp okf pro snapshot >> .okf/log.md` is the prescribed move wearing a
prefix, and an anchor that missed it would have made the same mistake in the
other direction. So is a short, named list of wrappers: `bundle exec okf pro
snapshot >> .okf/log.md` is *this repo's own* invocation of the prescribed move,
and an anchor that missed it counted a contributor's first command as friction.
The list is named rather than open, because an open rule is a way back to
matching a mention.

Splitting on separators is not shell parsing and may not become it. The residue
is written down because a bounded error is only bounded if it is: a separator
inside quoted content splits a command that is genuinely this gem's, and the
fragment holding the mutator word is read as somebody else's write. That
over-counts, which is the lesser error — it points a maintainer at a verb that
already exists, where the under-count it replaced hid the commonest shape there
is. Neither can refuse anything, and the prompt is still decided from the whole
command, so the guard's safety is untouched.

# It is telemetry, so it is not state

`okf pro state` is *cheap by contract* — `board.md`, `log.md`, two directory
globs, no concept parsed — and it briefly read the friction log as well, on
every call, for a field its human rendering never printed. Two things were wrong
at once, and the second is the durable one: an append-only file nothing prunes
had been added to the sources of the verb whose whole promise is that it is
cheap, and the only reader who could see the field was one asking for `--json`.

Friction is knowledge about the *tooling*, not about the bundle — which is
already why the log lives in `.tmp/` at the repository root rather than under a
root `okf validate` walks. `okf pro friction` is the verb that answers it. A
contract that names its sources is a contract to check when adding one.
