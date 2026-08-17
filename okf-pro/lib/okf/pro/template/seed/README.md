# Knowledge base

**Being good at something has a shape, and it is the same shape in every
craft.**

You know what you are committed to, and what you are not. You can tell what you
actually know from what you have merely read about. You do not relearn the same
lesson twice, because you wrote it down the first time. You can say where a
claim came from. When you take something new on, you know what it displaced.

Almost nobody is taught that shape. People arrive at it after ten years, by
accident and at their own expense, and plenty of very capable people never do —
not for lack of talent, but because nothing in an ordinary week ever forces the
question.

**You get there by structuring the way you work, not by trying harder.** That is
the whole method here: a small number of shapes — what you are committed to,
what you learned, what you read and who says so — each with one place it lives
and one form it takes, and a set of gates that refuse the edits that break them.
Give the practice a structure and the discipline stops being something you have
to remember to have.

It hands someone starting out the structure a professional already works inside,
and hands the professional a memory that does not quietly rot. It works the same
whether your craft is code, law, medicine, research, design or running a team,
because none of the four habits below is about any of those.

You work by talking to your agent, the way you already do. The difference is
that the agent is now held to those habits, and so are you.

> **This file is yours** — `okf pro upgrade` rewrites the governance files it
> owns and never touches this one. Rewrite the heading and the paragraphs above
> it the day this repository has its own story to tell. Everything below is your
> operating manual, and worth keeping until you know it by heart: your agent
> reads `.claude/skills/okf-pro/SKILL.md`, and this is the copy written for you.

## The four habits it structures

Each one is a thing good practitioners do and nobody does reliably from memory.
Here each is a shape with a place, a form, and a gate that refuses to let it
drift.

**You find out you are overloaded on the day it happens, not in hindsight.**
Five things in flight is a hard ceiling. Taking on a sixth means looking at five
existing commitments and saying which is worth less — which is the actual work
of prioritisation, and the thing nobody does voluntarily. Without a ceiling you
do not prioritise, you only add. A system where everything is in progress is a
school where everyone gets an A: the grade has stopped carrying information.

**You stop confusing what you read with what was generated near you.** Your
agent can summarise forty papers in an afternoon and cannot tell you that *you*
read them. Here it is allowed to write the summary and not allowed to write down
that you read it. Six months on, that distinction is the whole difference
between a knowledge base and a pile of plausible text.

**You notice a thing has gone quiet before it costs you.** A commitment nobody
has journaled in five working days gets asked about. Something you are blocked
on that went silent gets counted. A deadline landing Wednesday with nothing
pointed at it shows up on Monday — not because you configured a reminder, but
because it is an arithmetic consequence of the board being honest.

**You get a record that can contradict your memory of the quarter.** One line of
counters a day, computed rather than typed. "Inbox 14" tells you nothing; "+8
inbox, oldest now six days" tells you what your week did to you.

Everything stays on your machine. `.okf/` is files in this repository; nothing
is uploaded, and no part of the enforcement calls out anywhere.

## What you need

Git, Ruby, and a coding agent. The gates are written for
[Claude Code](https://claude.com/claude-code) and fire at its tool boundary.
Without an agent you keep the commit-time and CI doors — the bundle still cannot
go structurally wrong — but you lose the attestation gate, which is the most
valuable thing here. Worth knowing now rather than in week two.

```sh
okf skill ~/.claude                    # teach your agent the format
git config core.hooksPath .githooks    # arm this clone's commit door
```

Both are one-time and neither is optional. The first installs the **okf** skill,
which teaches your agent the *format* — what a concept is, what frontmatter it
carries, how links resolve. The **okf-pro** skill already sits in
`.claude/skills/okf-pro/` and teaches the *rules on top of it*; it deliberately
does not repeat the format, so skipping the install leaves your agent held to
invariants about something nobody taught it. Put it in your home directory and
every bundle on the machine is covered.

The second is per clone, because git hooks do not travel with a checkout.
Anyone cloning this later runs `gem install okf-pro` first, then both lines.

## A week with it

One ordinary week. Nothing is configured and nothing is automated away — the
system interrupts four times, and each interruption is the product working.

### Monday — something arrives

Someone drops a link in a group chat. You have eleven seconds before the
conversation moves on, so you tell your agent, in the words you actually saw:

> *"capture: link from the group about incremental static regen"*

One line lands in the Inbox, dated. No filename, no folder, no decision about
whether it matters. **Capture has no bar** — if it crossed your mind, five
seconds, in your own words. That is deliberate, and it is the part people get
wrong: capture that costs more than five seconds stops happening on exactly the
days it matters most, which are the busy ones.

By Tuesday afternoon two more have gone in the same way, unedited and unjudged.
The Inbox is allowed to be a mess. That is its job.

```markdown
## Inbox
- 2026-06-29 — link from the group about incremental static regen
- 2026-06-30 — Ana asked me to look at the pricing sheet before Thu
- 2026-06-30 — the Rust course — am I actually doing this or not
```

### Wednesday — the bar

Once a day, end of the afternoon is fine, you read the Inbox. Not to file it —
to decide what survives. This is the question everyone asks about a system like
this, and the answer has two halves:

**Capture has no bar. Triage is the bar.** Most Inbox lines never become
anything: they were noise, or already handled. A few are facts and get filed as
concepts. Only the remainder is work, and work has to fit five slots.

Four minutes of reading, three decisions. The group-chat link is a fact worth
keeping rather than work, so you ask your agent to file it in `reference/` and
it leaves the board. Ana's pricing sheet is real work with a real date, so it
gets promoted. The Rust course is the interesting one: read back on a Wednesday,
the honest answer is no — not "no forever", but to Backlog, where it costs
nothing and stops pretending to be active. That small act, repeated, is most of
what this does for you.

```markdown
**In flight: 5/5** · updated 2026-07-01

## In flight
- Q3 pricing model — next: send Ana the draft
- migration runbook — next: dry-run on staging
- hiring loop — next: write the take-home brief
- conference talk — next: outline section 3
- Ana's pricing sheet — next: read it, comment by Thu

## Backlog
- the Rust course

## Inbox
```

The board is full. Not "getting busy" — full, as a number, in a place you look
every day. Nothing has gone wrong yet, but the next thing that arrives has to
displace something, and you find that out the moment you try.

### Thursday — the first refusal

New work lands, it feels urgent, and you go to promote it:

```
RULE 3: 5 in flight against a cap of 5, so promoting makes 6. Promotion
requires demotion (`okf pro demote`), or a visible renegotiation of the cap —
which is journal-worthy, and yours to make.
```

Three things are true about that message and all three matter.

**It is not a suggestion.** The edit does not land. You cannot proceed by
ignoring it, which is what separates it from every tool that shows an amber
warning you learn to skip inside a fortnight.

**It offers you the escape.** You are allowed to work on six things. Change the
cap — it is your cap. The rule is not that five is correct; the rule is that
going to six is an act you performed, written in a header, mentioned in your
journal, and visible in December when you are working out why autumn felt like
that.

**It forces the comparison you were avoiding.** To promote the new thing you
have to look at five commitments and say which is worth less.

You demote the conference talk. Back to 5/5, with a different five.

### Thursday — the gate that matters most

You ask your agent to summarise a long paper into the bundle. Forty seconds
later there is a competent briefing in `reference/`, carrying `generated:`, and
a new line on the board:

```markdown
## To read
- /reference/consistency-models.md — summarised, not read
```

Here is the failure that prevents. In a normal setup that summary is now
indistinguishable from something you read and understood. Three months later you
cite it in an argument, and you have no way to know — not from the file, not
from memory — whether the claim passed through a human brain or was assembled by
a language model at 16:20 on a Thursday while you were doing something else.

So the agent is allowed to write the summary. It is not allowed to write down
that you read it.

Friday morning you actually read the paper. Twenty minutes, properly. Then you
tell the agent to mark it verified, and this is what happens:

```
This edit writes 'verified:' — owner attestation. The agent is the scribe;
your approval is the attestation. Approve ONLY if you have actually reviewed
this content yourself. If you have not, deny — unverified is the truth.
```

You approve, because you did read it. The block is written, the To-read line
comes off the board, and the concept carries a durable, checkable claim: a
person stood behind this, on this date. Deny it and nothing is written —
unverified stays the truth, which is not a defect to tidy away. And in an
unattended run, with nobody there to ask, the write is refused rather than waved
through.

### Friday — the day will not close

You try to end the session. It will not let you:

```
RULE 2 — before stopping:
— log.md has no Snapshot line under 2026-07-03. Append it before stopping —
  computed from the bundle as it stands:
  * **Snapshot**: inbox 0 (oldest 0d) · in flight 5/5 · waiting 2 (1 past chase)
    · backlog 4 · to read 0 · unverified briefings 1 · conflicts open 0
    · deadlines within 7d not in flight 1 · projects with 0 concepts 2
```

The gate computes the line and hands it over, so the fix is a paste. It is
numbers, not a reflection — judgment is kept out of it deliberately, because the
moment an opinion leaks into the counter it stops being comparable with
yesterday's. Your agent appends it, you write two sentences in the journal about
what the week meant, and the session closes.

A session where you read the bundle and changed nothing closes in silence. You
are not billed a ritual for opening a file.

## The following Monday — the return

Everything above was cost. Here is the return, and it exists only because last
week's line was recorded honestly. Your session opens with this, before you have
done anything and without your agent spending a call to fetch it:

```
Bundle state at session start — in flight 5/5 · backlog 4 · waiting 2 (1 past chase) · inbox 0 (oldest 0d) · to read 0 · conflicts open 0
Read the delta, not the status: a number that moved the wrong way is today's first signal.
```

And the numbers only mean something beside the previous ones:

| Counter | Mon 29th | Fri 3rd | What it says |
|---|---|---|---|
| inbox | 0 | 0 | Triage kept up. It did not accumulate. |
| in flight | 3/5 | 5/5 | You took on two more things and are at the ceiling. |
| waiting past chase | 0 | 1 | Something you are blocked on went quiet and nobody noticed. |
| unverified briefings | 0 | 1 | One summary is still unread. It is not knowledge yet. |
| deadlines <7d unclaimed | 0 | 1 | A date lands Wednesday and nothing in flight points at it. |

That last row earns the whole system. A deadline on Wednesday with nothing
pointed at it is a collision you can see three days out, and nobody had to
remember to check.

A standing count is wallpaper — a warning always on screen carries no
information and trains you to stop seeing it. The value is the comparison, which
is why the line is mechanical.

## Where things go

Most of a bundle is concepts, and one question routes them: **does it outlive
the work that produced it?** No → it belongs to a project. Yes, and someone else
wrote it → `reference/`. Yes, and you concluded it → `learnings/`. Yes, and it
is what a word means here → `glossary/`.

You do not write these by hand. You ask, and your agent files the Markdown:

```markdown
---
type: Briefing
title: Incremental static regeneration
description: What ISR actually guarantees about staleness, and where that breaks.
generated: { by: claude/opus-5, at: 2026-07-01T09:12:00Z }
stale_after: 2026-09-29
sources:
  - id: nextjs-isr
    resource: https://nextjs.org/docs/app/guides/incremental-static-regeneration
    title: Next.js docs — Incremental Static Regeneration
---

# What it guarantees
...
```

`generated:` says a machine wrote it and nobody has checked. `verified:` is the
one field your agent cannot set on its own.

| Where | What it holds |
|---|---|
| `reference/` | what other people produced — their claim, your summary, the source recorded |
| `learnings/` | conclusions of yours that outlive the work that produced them |
| `glossary/` | a word that needs one fixed meaning here because it means three elsewhere |
| `projects/` | work with a definition of done; one directory each |
| `areas/` | a standard held indefinitely — a level, not a finish line |
| `board.md` | the whole commitment surface, on one bounded page |
| `journal/` | one entry per working day: what happened, what it meant |
| `log.md` | what changed, and the day's counter line |
| `roadmap.md` | the quarter's intent, sparsely, linking out |

The first five are rooms for concepts. The last four are the running record —
`journal/` is prose, `log.md` is arithmetic, and keeping them apart is what makes
a counter comparable with yesterday's.

Everything else at the root — `CLAUDE.md`, `.claude/`, `.githooks/`, `.github/`
— is instruction or plumbing, and `okf` never looks at it. Scratch goes in
`.tmp/`, outside the bundle entirely.

If `projects/ areas/ reference/` looks familiar, it should: that is Tiago
Forte's PARA, and capture-then-triage owes a great deal to GTD. What is not
borrowed is the enforcement. PARA tells you where things go and nothing in it
stops you running eleven active projects or citing a summary you never read.

### The board's six sections

That is the board a few days in. This is the one you actually open today:

```markdown
---
type: Board
title: Board
description: The single page of forward state — every commitment, in six sections, on one page you can read at a glance.
---

# Board

**In flight: 0/5** · updated never

## In flight

## Backlog

## Waiting

## Inbox

## To read

## Deadlines
```

Only **In flight** is capped. How a line reaches each:

| Section | How something gets there |
|---|---|
| **Inbox** | you capture it. Rule 1's unsettled conflicts land here too — an unresolved contradiction is undifferentiated work until someone triages it |
| **In flight** | promoted from Inbox or Backlog, refused over the cap |
| **Backlog** | demoted from In flight, or moved across in triage |
| **Waiting** | you write it, when the next move belongs to someone else: who, what, when asked, and a literal `chase YYYY-MM-DD`. This is the section that rots silently — nothing here fails loudly, it just never arrives |
| **To read** | whoever files a briefing writes the line. Reading is what removes it, and only reading: a briefing your agent summarised is not read |
| **Deadlines** | you write it, date first — `- YYYY-MM-DD — what lands`. Outside the pipeline and outside the cap, because they arrive whether or not anyone acts |

## Why the rules cannot just be rules

Everything above depends on the refusals actually firing. A rule you can walk
past is a preference, and every knowledge system that has ever failed you failed
exactly that way: the discipline was real for three weeks, then it was optional,
then it was gone.

So the checks sit at three places, because each catches what the one before it
structurally cannot see.

| Door | Fires | Catches |
|---|---|---|
| `.claude/hooks/` | your agent's tool boundary | the agent editing a file |
| `.githooks/pre-commit` | `git commit` | what you edited yourself, where no hook fired |
| `.github/workflows/` | push | a clone that never ran the one-line setup |

All three fail **closed**. A gate that cannot run refuses rather than passing,
because a gate that waved edits through while its checker was missing would have
converted "unchecked" into "checked and fine" — and there is no later moment at
which anyone finds out.

## The commands, when you want them

Mostly you will not. Your agent runs these; the session banner tells it to, and
the point of the verbs is that shapes with exactly one correct form get written
correctly without anyone reconstructing the grammar from prose.

They are here because sometimes you want to look without opening a session:

```sh
okf pro state .           # the counts and the questions — "where am I?"
okf pro board .           # the lines themselves, one row each
okf pro audit .           # every invariant at once — the same check CI runs
okf pro unverified .      # what still awaits your read
okf validate .okf         # conformance — is this a legal OKF bundle?
okf lint .okf             # curation — is it a well-kept one?
```

The `okf pro` verbs take the repository root, because they reason about the
bundle, the git history and the hooks together. The kernel's two take the bundle
itself. There are writers as well — `capture`, `promote`, `demote`,
`journal open`, `close` — and those are the ones your agent uses on your behalf.
`okf pro --help` lists them all.

**What the day costs you.** Capture is five seconds a line. Triage is ten
minutes, once. The closing sitting is another ten. Twenty to twenty-five minutes
of *your* time on a day you worked, nothing at all on a day you did not, and
your agent pays none of it.

## Tuning

Three numbers ship as defaults, and all three are probably wrong for you:

| Number | Default | Where it lives |
|---|---|---|
| In-flight cap | 5 | the `**In flight: 0/5**` header at the top of `.okf/board.md` |
| Dormancy window | 5 working days | Rule 3 in [the okf-pro skill](.claude/skills/okf-pro/SKILL.md) |
| Staleness windows | briefings +90d, terms +180d, measured external figures +90d | the frontmatter guide in the skill, owned by [`.okf/areas/corpus.md`](.okf/areas/corpus.md) |

They are visible-and-wrong by design. A default wrong in plain sight gets
corrected in week two; a hidden one gets worked around forever, and the
workaround becomes the system. **Change the number, never hide it** — and for
the staleness windows, record the decision in `areas/corpus.md` first, then the
skill, then a dated `log.md` line, so the standard never lags the rule.

## Turning it off, and leaving

A system built out of refusals owes you a way to stop being refused. There is no
secret flag, and that is deliberate — a gate with an off switch an agent can
reach is not a gate. Everything here is you editing a file.

**One gate, off.** Delete its entry from `.claude/settings.json`. Six are listed
there by name — `guard-verified`, `journal-guard`, `shell-guard`, `post-edit`,
`stop-gate`, `session-context` — one command each, and removing one has no
effect on the others.

**All the agent-time gates, off.** Remove the `hooks` block from
`.claude/settings.json`. You keep the commit and CI doors, so the bundle still
cannot go structurally wrong; you have only stopped being interrupted while you
work.

**The commit door, off.** `git config --unset core.hooksPath`, or
`git commit --no-verify` for a single commit you need through right now.

**All of it, off.** Do both of the above.

**Leaving entirely.** Delete `.claude/`, `.githooks/`, `.github/` and
`CLAUDE.md`. What remains is `.okf/` — Markdown with YAML frontmatter, readable
by anything, portable to any editor, and still a valid OKF bundle that
`okf validate` passes on its own. Nothing you wrote is trapped in this
repository's machinery, and nothing about the format depends on the enforcement.
That is the point of building on a spec rather than a schema of someone's own.

One thing you cannot do is turn a gate off with an environment variable. There
is none to set: the enforcement layer reads no environment variable to decide
whether a check runs. A gate a stray `export` could disable is one you would
have no reason to trust.

## Honest limits

**This is a passport, not a lie detector.** It can prove where a claim came
from, who summarised it, and whether a human ever checked it. It cannot tell you
whether the claim is true. What it buys you is that a well-sourced mistake stays
*catchable* — traceable, dateable, and you can find everything downstream of it.
That is the best honest promise a knowledge system can make, and anything
promising more is selling something.

**Reconciliation is only as good as your vocabulary.** When you file something
new, the system makes you search for what it collides with — and that search is
only as good as the words you thought to look for, which is why naming things
well is load-bearing here rather than cosmetic.

**The counters can drift between sessions.** A number changed by hand in your
editor stays uncorrected until the next session closes, because the day's gate
checks that a snapshot is *present*, not that yesterday's was current. A
late-and-trusted gate beats a punctual one nobody reads.

**It is built for one person.** Every rule here — your cap, your approval, your
day — assumes a single owner. Two people sharing one board is not a supported
arrangement, and nothing stops you trying it.

*The week shown above illustrates the mechanics; it is not a record of a real
week.*
