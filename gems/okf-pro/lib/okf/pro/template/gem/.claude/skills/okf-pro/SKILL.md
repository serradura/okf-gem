---
name: okf-pro
description: Operating rules for the .okf/ knowledge bundle — filing new concepts, the board, the journal, the daily snapshot, closing work, source attribution, and the generated/verified attestation policy. Use before reading from or writing anything into .okf/.
---

# Operating the bundle

Everything here is relative to `.okf/`, the bundle root — `reference/`
below is `.okf/reference/` on disk, and a link written
`/reference/thing.md` inside a concept resolves there.

## What to load

This file is the whole of the three rules and the routing question, and
it is the part every session needs. Two things come before opening any
guide: the CLI already answers most questions about state, and the line
shapes are below.

### Ask the CLI before you read a file

State is computed, not read. Every row below is one call answering what
several `cat`s answer, and the first row costs nothing at all — it is
already in front of you.

| to answer | run | not |
|---|---|---|
| what is on the board / what is in flight | *(already in the session banner)* | `cat board.md` |
| the board after you changed it | `okf pro state` | re-reading the file |
| one row per board line, with dates and links | `okf pro board` | counting headings by eye |
| what awaits the owner's read | `okf pro unverified` | grepping frontmatter |
| the day's snapshot line | `okf pro snapshot` | computing it by hand |
| every invariant at once | `okf pro audit` | — |

And five writes have exactly one correct form, so they are verbs rather
than shapes to reconstruct. Each is additive and targeted: it appends a
line or edits the line you named, refuses if the change it computed is
not the change it declared, and never rewrites a file.

| to do | run |
|---|---|
| capture something into the Inbox | `okf pro capture "the words you heard"` |
| move a line to In flight (refuses over the cap) | `okf pro promote <selector>` |
| move one back to Backlog | `okf pro demote <selector>` |
| open today's journal day and index it | `okf pro journal open` |
| the three mechanical closing moves | `okf pro close <project>` |

A `<selector>` is a `/projects/<slug>` link, a bare slug, or a substring
only one line carries — never a position. Two lines matching is a
refusal, not a coin toss.

Add `--json` to `state`, `board`, `snapshot`, `unverified` or
`friction` when you want to compute on the answer rather than read it;
`okf pro state --full` adds the corpus-derived parts behind one parse.
`audit` and `records` answer with their exit code and take no flags.

**The line shapes, so you do not have to open a guide for them.** A
board line starts `- ` at column zero — a `*` bullet or an indented dash
is invisible to every counter, including the cap. Inbox and Deadlines
lines lead with the date: `- YYYY-MM-DD — <the words>`. A Waiting line
carries `chase YYYY-MM-DD`, literally. A conflict line is an Inbox line
reading `- YYYY-MM-DD — Resolve: [/a.md] says X, [/b.md] says Y —
noticed while <doing what>`. The closure marker is the word then the
date with only spaces, a colon, a dash, asterisks or an opening
parenthesis between: `# Title — closed 2026-08-12`. That is a deliberate
partial duplication of the guides, and the guides remain the full
reference — this is here so the commonest question does not cost a file
read.

### The guides

Each *act* has its detail one file away. Load the one the task calls
for, not all five.

* [guides/frontmatter.md](guides/frontmatter.md) — the *trust* family
  this profile adds on top of the format: `generated:`, `verified:` and
  the tiers they produce, `status:`, and the `stale_after:` windows.
  **Before writing any concept, and whenever provenance is the
  question.**
* [guides/board.md](guides/board.md) — the six sections, the date
  grammar the counters actually read, and what makes a line invisible
  to them. **Before editing `board.md`.**
* [guides/attribution.md](guides/attribution.md) — `sources:`, and the
  keyed footnotes that tie one claim to one source. **Before filing
  anything into `reference/`.**
* [guides/closing.md](guides/closing.md) — the four moves that close a
  piece of work, and the exact spellings of the closure marker.
  **Before marking a project closed.**
* [guides/okf-rules.md](guides/okf-rules.md) — the *format's* floor,
  which holds for any OKF bundle and not just this profile: the three
  required frontmatter keys, directory indexes, link form, the log
  entry. **When `okf validate` or `okf lint` disagrees with you.**

Read this list permissively. A guide that is missing does not suspend
the rule it explains — the three rules below are operative on their own,
and the gates enforce them whether the file explaining them was read or
not. A file in `guides/` that this list does not mention still counts:
the index is a map, not a permission list, and adding your own guide
beside these is expected. Anything here you do not recognise — an extra
heading, a `<!-- rule: … -->` marker, a file kind you have not seen — is
left alone rather than treated as an error.

## The three zones

| Zone | Directory | What lives there |
|------|-----------|------------------|
| **KNOW** | `reference/` | What other people produced — summarised, cited, attributed. |
| | `learnings/` | What I concluded, true beyond the work that produced it. |
| | `glossary/` | What a word means here, when it means three things elsewhere. |
| **ACT** | `projects/` | Work with a definition of done. Closes. |
| | `areas/` | A standard held indefinitely. Never closes. |
| **TIME** | `board.md` | The single page of forward state — the whole commitment surface. |
| | `journal/` | The backward record, one entry per day, append-only. |
| | `roadmap.md` | The quarterly wavelength. Sparse, links out. |

## Where a new concept goes

One question routes almost everything: **does it outlive the piece of
work that produced it?**

* **No — it is work-scoped** → `projects/<slug-or-key>/`. Meeting notes,
  the decision that only makes sense inside this project, the finding
  that is really a status update.
* **Someone else wrote it** → `reference/`. Their document, their claim,
  your summary of it, with the source recorded.
* **A conclusion of mine, true beyond one piece of work** → `learnings/`.
* **A term needing a fixed meaning** → `glossary/`.
* **What happened on a day** → `journal/`.

When two of these fit, the tiebreak is retrieval: file it where you
would look for it in six months, having forgotten which project it came
from.

When **none** of them fits, prefer the room that nearly does. Do not
open a catch-all: a room meaning "everything else" is a blind spot by
construction — things enter it and nothing enumerates them again — and
nobody has ever searched for the thing that did not fit.

The five are the starting set, not the closed set. A sixth room is
earned by an incident rather than anticipated: once the same misfiling
has actually cost you something, make the room, name it for the
question it answers rather than for its subject, and link it from
`index.md` — an unlinked directory is a room nobody can find.

Material you are *mirroring* rather than summarising — a script, run
instructions, a vendored copy — already has a home in the format: OKF
§6.3's `references/`. Note the plural: this bundle's `reference/` holds
your summaries of other people's work, and the two are one character
apart.

Before minting any name — a concept's title, a tag, a type — read the
naming policy in `/areas/corpus.md`. It is short, it is the adopter's
own standard, and a name that collides with what a word already means
in their domain is a file nobody can search for.

## Rule 1 — Writing is reconciliation

Before a new concept settles — an inbox line promoted, a briefing
created, a finding recorded — search the bundle for what it collides
with: `okf search` on the claim's key terms, and read the bodies of
what comes back — not a glance at titles.
Three outcomes. It contradicts nothing: file it. It supersedes
something: correct the loser **now** — title and `description:` first,
`status: deprecated` on its frontmatter, superseded reasoning into
`<details>` — because ingestion is the only moment both claims are in
front of someone and the cost of noticing is at its minimum. The status
field is the machine-readable half of that move: it is what lets a later
search see that a collision was already settled instead of re-litigating
it, and the reconcile gate says so when it fires next.

Or the conflict cannot be settled on the spot: **file it, do not resolve
it** — one dated line on the board, both sides linked:

```
- <date> — Resolve: [/reference/a.md] says X, [/glossary/b.md] says Y — noticed while <doing what>
```

An unresolved contradiction is work. It competes for attention like
work, and only resolving it takes the line away. Know what this rule
cannot do: it catches collisions **as well as your search vocabulary
does, and no better** — which is why it has a second checkpoint:
whenever any search returns two concepts that disagree, that collision
gets the same board line, whatever you were looking for. And it is why
`index.md` curation and `glossary/` naming are load-bearing rather than
hygiene: the corpus's consistency is bounded by its findability.

## Rule 2 — The day ends with a snapshot, and the delta is the signal

The end-of-day sitting (journal entry + board update, one habit)
appends one line to `log.md`, last entry under the day:

```
* **Snapshot**: inbox N (oldest Xd) · in flight k/CAP · waiting N (M past chase) · backlog N · to read N · unverified briefings N · conflicts open N · deadlines within 7d not in flight N · projects with 0 concepts N
```

The line is mechanical and belongs to `log.md`, not the journal —
counters are neither hunch nor judgment. Mechanical means derivable:
`okf pro snapshot .` computes the line, and the stop gate
refuses one that disagrees with the board it summarises — a counter
that drifted is a confession that lies. The deadlines field is a
confessed blind spot: a date due within seven days that no in-flight
line links is a collision visible before it lands. Its value is the
comparison with yesterday's line: "+8 inbox, oldest now 6d" is
information; a standing count is wallpaper, and a warning that is
always present carries zero information. If a delta deserves a sentence
of judgment, that sentence goes in the journal, which is where judgment
lives. And a day too heavy to journal gets the mechanical fallback:
reconstruct the entry from `log.md` and git history, and say in the
entry that it was reconstructed — a thin honest record beats a gap that
reads as a quiet day.

A brand-new bundle ships dateless — an undated `log.md`, an empty
`journal/`. That is day-zero state, not a defect: never backfill an
initialization entry or a day nobody worked. The first working day
creates its own `## <date>` section and first journal entry, and the
stop gate hands you the exact snapshot line to append.

## Rule 3 — In flight is a budget

At most **5** demands in flight; `board.md` carries `In flight: k/5` at
the top. Promoting from Backlog requires demoting something — or
renegotiating the cap, which is allowed, visible, and
**journal-worthy**, because "the week the cap went to 6" is exactly
what a review needs and exactly what a silently exceeded cap hides. The
cap's job is not to make five the right number; it is to make overload
undeniable on the day it happens. Two exemptions: Deadlines (they come
due regardless of anyone's budget) and Backlog (captured, not claiming
attention). One question the budget asks on its own: an in-flight
demand no journal entry has linked in **5 working days** gets the
dormancy line — still in flight, or backlog pretending? Either answer
is fine; holding a slot without moving is not. The session banner asks
it mechanically, and stays quiet while the journal is younger than the
window — a bundle in its first week cannot be dormant, only new.
<!-- rule: okf-pro-dormancy-window -->
