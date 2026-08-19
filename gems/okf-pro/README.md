<h1 align="center">OKF Pro</h1>
<p align="center"><em>Structure for making things happen!</em></p>

**Get better at what you do by structuring how you do it.** Being good at
something has a shape — you know what you are committed to, you can tell what
you know from what you have merely read, you do not relearn the same lesson
twice, you can say where a claim came from. Most people arrive at that shape
after ten years, by accident. This is the shape written down and held in place.

An agent that writes notes accumulates a folder. An agent held to a few
invariants accumulates a memory. okf-pro is those invariants, run at three doors
— while the agent edits, when you commit, and again in CI — plus the
`okf pro setup` that writes the whole arrangement into a repository.

It is **a profile of [OKF](https://okfgem.com)**: one opinionated shape a
knowledge bundle can take, and the gates that hold it in that shape. OKF is an
open format for durable knowledge — directories of Markdown with YAML
frontmatter, read by people and agents alike. Any OKF bundle is already a brain:
authored concepts, a graph, retrievable. That stays general. What this adds is a
bundle that also refuses to let its own knowledge rot.

**What it is for, plainly.** One person's working practice, in **its own
repository** — not `.okf/` inside your application. It is domain-agnostic by
construction: none of the rules mentions code, so it works the same for law,
research, medicine, design or running a team. `setup` writes a whole
repository's worth of files (`CLAUDE.md`, `README.md`, a workflow), so point it
at an empty directory. It will complete an existing one — nothing is ever
overwritten — but that is the recovery path, not the design.

**It is not a paid tier** — Apache 2.0, like everything else in the ecosystem.
The name is an equation, and it is the whole argument in miniature:

> **pro(file) + pro(cess) = pro(fessional)**

A *profile* is the structure: the term of art for a constrained application of a
general format, which is exactly what this is, and what holds your *pro(gress)*
— the board, the journal, the roadmap. A *process* is that structure enforced
rather than remembered. Neither alone makes anyone better at anything; together
they are what a professional actually has, and what nobody is handed at the
start.

```sh
gem install okf-pro                    # brings okf with it
okf skill ~/.claude                    # the format itself — once per machine

mkdir my-brain && cd my-brain          # its own repository, not your app's
git init
okf pro setup .                        # bundle + hooks + pre-commit + CI + skill
git config core.hooksPath .githooks    # per clone; hooks do not travel
```

`okf pro` appears in `okf help` because this gem registers itself through okf's
plugin seam; there is no second binary.

**The second line is a dependency, not a nicety.** Two skills are involved and
they do different jobs. okf's teaches your agent the *format* — what a concept
is, what frontmatter it carries, how links resolve, which verb answers which
question. okf-pro's, installed into the repository by `setup`, teaches the
*rules on top of it*. Skip the first and you have an agent held to invariants
about a format nobody taught it, which fails in the least useful way: it knows
the board is capped at five and not what a concept looks like.

Install it into your home directory rather than a project, and every bundle on
the machine is covered — the ones this gem governs and the ones it does not.

**What you need.** Git, Ruby ≥ 2.4, and a coding agent — the agent-time gates
are written for [Claude Code](https://claude.com/claude-code) and fire at its
tool boundary. Without one you keep the commit and CI doors and lose the
attestation gate, which is the most valuable thing here. Worth knowing before
you invest a week.

## What it enforces

Three laws, and the reason each exists.

**Rule 1 — writing is reconciliation.** Before a new concept settles, the corpus is
searched for what it collides with. A contradiction that cannot be settled on
the spot becomes one dated line on the board — because an unresolved
contradiction is work, and work that is not on the board is work nobody is
tracking.

**Rule 2 — the day ends with a snapshot.** One mechanical line under the day's heading in
`log.md`: inbox, oldest, in flight, waiting, backlog, to read, unverified
briefings, conflicts, deadlines. Its value is the delta. A standing count is
wallpaper; "+8 inbox, oldest now 6d" is information. The gate computes the line
and refuses one that disagrees with the board it summarises.

**Rule 3 — in flight is a budget.** Five demands, and promoting from the backlog means
demoting something — or renegotiating the cap, visibly, in the journal. The
cap's job is not to make five the right number; it is to make overload
undeniable on the day it happens.

And one rule that is not a law but is the reason the rest can be trusted: an
agent may hold the pen for `verified:`, but the write is routed to you for
approval, and **the approval is the attestation**. Absent `verified:` on a
generated concept is the truth about it, not a defect to be tidied away.

## A day with it

**You do not run these commands. You talk to your agent, the way you already
do** — the verbs below are what it reaches for, and the gates hold you both.
Here is the shape of a day, and the vocabulary the rest of this page uses.

**Session start.** Your agent is handed the board state before it does anything,
by the SessionStart banner, so the first question of a session is answered
without a call being spent on it. `journal open` creates today's entry.

**All day.** *"capture: Ana wants the pricing sheet before Thursday."* Five
seconds, in your own words, into the board's **Inbox**. No filing, no decision.

**Once a day.** You read the Inbox and triage it — the only part that is
genuinely yours, because it is judgement. Most lines die there. What is real
work gets promoted into **In flight**, which holds at most five, and a sixth is
refused until something is demoted. That refusal is the point: it makes you
compare five commitments and say which is worth less, which is the work of
prioritisation nobody does voluntarily.

**Anything worth keeping.** *"file a briefing on this in reference/."* Your
agent writes the concept, carrying `generated:`. It may not add `verified:` —
that write is held and put to you, and your approval is the attestation.

**End of day.** The stop gate refuses to close a day you changed until its
counter line is in `log.md`, and computes the line for you so the fix is a
paste. Judgement goes in the journal, arithmetic in the log, and they stay apart
because the moment an opinion leaks into a counter it stops being comparable
with yesterday's.

The return is the delta. "Inbox 14" tells you nothing; "+8 inbox, oldest now six
days" tells you what your week did to you — and a deadline landing Wednesday
with nothing in flight against it shows up on Monday, as an arithmetic
consequence of the board being honest rather than a reminder anyone configured.

Call it twenty minutes of *your* time on a day you worked, and nothing at all on
a day you did not, because a session that changed nothing closes in silence.
Your agent pays none of it.

## The three doors

| Door | When | What it sees |
|---|---|---|
| the agent's hooks | the agent's tool boundary | every write into the bundle, before and after |
| `.githooks/pre-commit` | `git commit` | the **staged** tree, plus the append-only record |
| `.github/workflows/` | push | everything, on a machine that configured nothing |

They exist separately because each sees edits the others cannot. Hooks fire only
inside the agent; git hooks only on a clone that ran `git config core.hooksPath`;
CI only on what was pushed. Edit a file in your own editor and the agent hooks
never see it at all: the commit door catches it if you armed one, and CI catches
it either way.

The first door is six checks, and what each one does when it fires:

| Check | Fires on | What it does |
|---|---|---|
| `guard-verified` | a write carrying `verified:` | **holds the write** and puts it to you — approve and it lands, deny and it does not |
| `journal-guard` | a write into `journal/` | **refuses** editing a past day; asks before creating one |
| `shell-guard` | a Bash command | **holds it** and puts it to you when the command would write into the bundle |
| `post-edit` | after every write | **reports** — validate, lint, and Rule 1's collisions |
| `stop-gate` | end of session | **refuses** to close a day you changed without its snapshot |
| `session-context` | session start | **informs** — hands the agent the board state, costing no call |

Two of the six hold a tool call *before* it runs and hand you the decision;
two refuse outright; one reports after the fact; one only informs. Rule 1 is on
the reporting side deliberately. It fires when a *new* concept is
written, names the existing concepts sharing its vocabulary, and tells the agent
to settle it before continuing — a collision is a judgement, and a gate that
hard-blocked on shared words would be wrong far more often than right.

`settings.json` points all six at one bash wrapper, `.claude/hooks/run`, rather
than at `okf` directly. That indirection is the contract below being kept: a
Ruby checker cannot refuse on its own absence, so something already running has
to.

## The contract

> Blocking checks fail **closed**. Feedback checks fail **loud**. No check ever
> fails **silent**.

The third clause is the one that shapes the code. A gate that is sometimes
absent and does not say so converts "unchecked" into "checked and fine", and
there is no later moment at which anyone finds out. So a missing checker, an
unloadable library, a stray `okf` on `PATH`, an exit code the gate did not
choose — each of them refuses, by name.

## Commands

```
okf pro setup      [DIR]   create or complete an agent's brain in DIR (default .)
okf pro upgrade    [DIR]   rewrite the gem-owned governance files; stage the rest
okf pro state      [DIR]   what is on the board, in one call — --full adds the corpus
okf pro board      [DIR]   one row per board line: section, dates, age, links
okf pro capture    TEXT    append a dated Inbox line
okf pro promote    SEL     Inbox or Backlog to In flight, refusing over the cap
okf pro demote     SEL     In flight back to Backlog
okf pro journal    open    create today's journal day and index it
okf pro close      SLUG    the three mechanical closing moves for a project
okf pro audit      [DIR]   every invariant at once — the CI door
okf pro records    [DIR]   does the staged commit rewrite a past journal day?
okf pro snapshot   [DIR]   compute the day's counter line (prints, never writes)
okf pro unverified [DIR]   concepts still awaiting the owner's read
okf pro friction   [DIR]   what was done by hand that a verb could do (--clear resets)
okf pro skill      DEST    (re)install the agent skill on its own
okf pro hook       CHECK   run one gate against a hook event on stdin
```

Three exit conventions, and the differences are deliberate:

* **Readers** — `audit`, `records`, `state`, `board`, `snapshot`, `unverified`,
  `friction` — follow okf's: `0` clean, `1` findings, `2` could not run.
* **Writers** — `capture`, `promote`, `demote`, `journal`, `close` — answer `0`
  or `2` and never `1`. Either the edit landed, or nothing was touched: a rule
  refused it, a selector matched nothing or matched twice, or the conservation
  guard caught a delta that was not the declared one. `2` on a writer always
  means the file is exactly as it was.
* **`hook`** follows the Claude Code hook protocol — `0` passes, `2` blocks. The
  protocol reads `1` as non-blocking, so a gate that exited `1` would let the
  edit through.

`state`, `board`, `snapshot`, `unverified` and `friction` take `--json` (and
`--pretty`), because their consumer is as often an agent as a person. `audit`
and `records` do not: what they answer with is the exit code, and a pipeline
reads that. `okf pro --help` lists what each verb takes.

Against a bundle a few weeks in — not a fresh one, which reports zeroes:

```console
$ okf pro state
Board — in flight 1/5 · backlog 0 · waiting 1 (1 past chase) · inbox 2 (oldest 4d) · to read 1 · deadlines 1 · conflicts open 0
Deadlines within 7d with nothing in flight against them:
  - 2026-08-19 — insurance renewal lapses
Log — newest day 2026-08-16 · journal for 2026-08-17 not opened
Open projects (1): home-move
As of 2026-08-16, the last logged snapshot — unverified briefings 1 · projects with 0 concepts 1 (`--full` recomputes these live)
```

### The writers, and why they refuse

Five shapes have exactly one correct form, and reconstructing them from prose
on every use is what an agent was doing instead: a third of one measured
session's tool output was this gem's own guides, read to learn where a date
goes. The verbs know.

They are **additive and targeted, never regenerative**. A verb appends a line
or edits the line it was given, and none of them rewrites a file. That is
enforced rather than promised: each one computes its new text purely, declares
the delta it intends, and a conservation guard compares line multisets before
anything is written. If the actual delta is not the declared one — a line
dropped alongside the append, a promotion that silently did nothing — it exits
2 and the file is untouched.

```console
$ okf pro capture "the invoice from acme needs checking"
okf pro capture — one line added to Inbox:
  - 2026-08-17 — the invoice from acme needs checking

$ okf pro promote "parking permit"
okf pro promote — RULE 3: 5 in flight against a cap of 5, so promoting makes 6. Promotion requires demotion (`okf pro demote`), or a visible renegotiation of the cap — which is journal-worthy, and yours to make.
```

Selectors are keyed, never positional: a `/projects/<slug>` link, a bare slug,
or a substring only one line carries. Two matches is a refusal listing both,
not a coin toss — agents rewrite, and "the third line under Backlog" names a
different commitment after any edit anyone makes.

And what stays judgment stays yours. `close` performs the three mechanical
moves — the marker, the board lines, the log entry — and reports the fourth,
extracting the durable part to `learnings/`, as owed. No verb writes a concept
body, and none sets `verified:`.

## What `setup` writes

```
.okf/                 the bundle: board, log, journal, and five zones, all empty
.claude/hooks/run     the fail-closed wrapper the six agent gates point at
.claude/settings.json the hook table
.claude/skills/       the okf-pro skill — the operating rules, in full
.githooks/pre-commit  the commit door
.github/workflows/    the push door
CLAUDE.md  .gitignore  .tmp/
README.md             a front page for the adopter, theirs to rewrite
```

The five zones are `reference/` (what other people produced), `learnings/` (what
you concluded), `glossary/` (what a word means here), `projects/` (work with a
definition of done) and `areas/` (a standard held indefinitely). A concept is
one Markdown file in one of them:

```markdown
---
type: Briefing
title: Incremental static regeneration
description: What ISR actually guarantees about staleness, and where that breaks.
generated: { by: claude/opus-5, at: 2026-08-17T09:12:00Z }
stale_after: 2026-11-15
sources:
  - id: nextjs-isr
    resource: https://nextjs.org/docs/app/guides/incremental-static-regeneration
    title: Next.js docs — Incremental Static Regeneration
---

# What it guarantees
...
```

`generated:` says a machine wrote it and nobody has checked. Adding `verified:`
is the write that routes to you, and until it does the concept is **unverified**
— which is a true statement about it, not a defect.

**Structure, not content.** Every zone ships with an index describing its room
and listing nothing; the first knowledge filed is yours. And **no date ships
anywhere**: a template is cloned an unknowable number of days after it is
built, and dormancy measures a bundle's age by its oldest journal entry — a
shipped entry would make a fresh clone read as an old one.

Run it again whenever you like. Files you already have are never overwritten:
the template's version is staged beside yours as `<path>.okf-pro-new` for you
to merge. `okf pro upgrade` refreshes the four files this gem owns — the hook wrapper,
the pre-commit hook, the workflow and the okf-pro skill — and leaves everything
else, including `CLAUDE.md`, `README.md`, `settings.json` and all of `.okf/`,
exactly as you left it.

`journal/` and `log.md` are both dated and easy to confuse: the journal is
*prose* — one entry per working day, what happened and what it meant — and the
log is the *record*, one line per change plus the day's counters. Judgement goes
in one, arithmetic in the other, and keeping them apart is what makes a counter
comparable with yesterday's.

Concepts themselves are written by your agent, not by a verb: you ask for a
briefing and it files the Markdown. That is the deliberate division — the verbs
own the shapes that have exactly one correct form, and everything requiring
judgement stays with you and your agent.

The seeded `README.md` is the adopter's manual — the first hour, the refusals,
the tunable numbers, and how to turn every gate off. This page is the gem's;
that one is the repository's.

## Prior art

If `projects/ areas/ reference/` looks familiar, it should: that is Tiago
Forte's PARA, and capture-then-triage owes a great deal to GTD. What is not
borrowed is the enforcement. PARA tells you where things go, and nothing in it
stops you running eleven active projects or citing a summary you never read.
The one structural departure is splitting PARA's single Resources room into
`reference/`, `learnings/` and `glossary/` — three retrieval questions asked at
three different moments, argued in the seeded `areas/corpus.md`.

## Turning it off

A system built out of refusals owes you a way to stop being refused, and every
lever is a file you edit. One gate: delete its entry from
`.claude/settings.json`. All the agent-time gates: remove the `hooks` block,
keeping the commit and CI doors. The commit door: `git config --unset
core.hooksPath`, or `--no-verify` for one commit. Leaving entirely: delete
`.claude/`, `.githooks/`, `.github/` and `CLAUDE.md`, and `.okf/` remains a
valid OKF bundle that `okf validate` passes on its own.

There is no environment variable that turns a gate off, because none is read: a
gate a stray `export` could disable is one you would have no reason to trust.
The seeded README documents each lever in full.

## What this gem does not do

It answers no question okf can answer. Conformance, curation, search, the
graph, the trust tiers — all of that is the kernel's, and a second
implementation that disagreed with it by a day or a rule would be worse than
none. What lives here is the policy on top of those answers, and the machinery
that makes a gate refuse rather than shrug.

It is also **a passport, not a lie detector**: it can prove where a claim came
from, who summarised it, and whether a human ever checked it, and it cannot tell
you whether the claim is true. What that buys is a well-sourced mistake staying
catchable. The collision check, likewise, is only as good as the vocabulary you
searched with. And every rule assumes **one owner** — your cap, your approval,
your day; two people sharing one board is not a supported arrangement.

Its own knowledge bundle ships inside the gem, at `.okf/` — the non-obvious
parts, written down: the three ways the plugin seam let an unchecked edit
through, the check the gate skipped in silence, and why a stray binary on
`PATH` cannot be caught by reading an exit code.

## Licence

Apache-2.0. Built by [Rodrigo Serradura](https://github.com/serradura).
