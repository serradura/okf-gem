---
type: Learning
title: The seeded README is the only document written for the owner
description: Every other seeded file addresses the agent, so the adopter's README carries the exit, the limits and the price — and a fresh reader can measure whether it does.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# What the seeded README is for

`setup` writes two prose files for humans and one for the machine. `CLAUDE.md`
and `.claude/skills/okf-pro/` address the **agent**: the routing table, the
frontmatter policy, the line grammars. `README.md` is the only thing in the tree
addressed to the **person who owns the repository**, and it is the file they
land on when they open the directory.

That makes it a product surface rather than a courtesy, and it has to answer the
questions the skill never will, because the agent has no use for them: what does
a day cost me, what will this refuse, how do I change the numbers, and how do I
turn it off.

# The exit is the section that buys the rest

A layer built out of refusals owes the reader a way to stop being refused, and
the section documenting it is worth more than any section arguing the benefits.
Stated as four escalating levers — one gate, all the agent-time gates, the
commit door, everything — plus what survives removal, it converts "this thing
constrains me" into "this thing constrains me *and told me where the door is*".

Two properties make it real rather than reassuring:

* **Every lever is verified by running it**, not described from the source. A
  documented escape that does not work is worse than none — see
  [a rule you can walk past](/design/a-rule-you-can-walk-past.md), whose fourth
  clause is exactly this.
* **What survives is stated.** Delete the machinery and `.okf/` is still a
  bundle `okf validate` passes, because the format was never the enforcement's
  to own. That is the payoff of building on a spec, and it is only worth
  anything if the README says so out loud.

The absence of an environment kill switch belongs here too, as a *feature* with
its reason attached: a gate a stray `export` could disable is one nobody has
reason to trust.

# Measuring a README instead of proof-reading it

A document's defects are not a matter of taste, and the maintainer is the worst
available judge of their own page because they cannot un-know what it omits. The
method that works: hand a reader **only that file**, ask a fixed set of a
reader's real questions, and record which ones came back CONFIDENT, PARTIAL and
BLANK.

The blanks are the finding. Three surfaced here that no amount of re-reading had
caught, in a file its author considered finished: no exit, no non-promises, and
no picture of `board.md` — the one file the whole system pivots on, quoted only
in fragments. A reader cannot report a section that was never there; they can
report a question they could not answer, and those are the same fact.

# The two rules the measurement produced

**The same content can be right in one document and wrong in another, because of
where the reader is standing.** The four-way gloss on the word *Pro* is good
writing and belongs on the package page, where "is this a paid tier?" is a live
misreading worth killing in the first screen. Dropped into the adopter's own
repository it was the single sentence that lost the reader — someone standing in
a new directory is asking what to do, not what the name means. Neither placement
is a quality judgement about the prose. Position is the variable.

**The loudest claim is the one that must carry evidence.** This page's method is
claim-plus-evidence — the cap refusal, the snapshot line and the promote
conflict are all shown as real output. The attestation gate was asserted as "the
most valuable thing here" four separate times and shown exactly never, and it
was the only claim a fresh reader singled out as unevidenced. A document that
proves its cheap claims and asserts its expensive one has inverted its own
argument: the reader calibrates on what you demonstrate, so the thing you most
want believed is the thing that can least afford to be described.

# The manual is for the practice, not the command set

The first draft of this page was a CLI manual: every worked example a
`$ okf pro …` transcript, a command table high on the page, and a "first hour"
that was a list of verbs to type. It read as competent and it sold the wrong
thing, because it described the machinery instead of the practice the machinery
exists to hold.

The system is agent-facilitated. The owner's actual moves are: *say what
happened* to their agent, *triage* once a day, *approve or deny* an attestation,
and *read the delta* at the next session start. The verbs are what the agent
reaches for — the session banner tells it so in as many words — and the owner
can go a week without typing one. A page whose every example is a shell prompt
teaches the reader they are operating a tool, when what is being offered is a
way of working.

So the narrative shows board states and refusal messages, and the commands get
one section, late, framed as what your agent uses and what you may occasionally
want to run yourself. The gem's README can afford to lead with the command set —
its reader is choosing a package — and the adopter's cannot.

# The pitch is the practice, not the preservation

The defensive framing — *your knowledge will rot and this stops it* — is true and
undersells the thing. The offer is that being good at any craft has a shape:
knowing what you are committed to, telling what you know from what you have
merely read, not relearning a lesson twice, being able to say where a claim came
from. Most people reach that shape after a decade, by accident, and many never
do — because nothing in an ordinary week forces the question.

The mechanism is structure rather than effort, and saying so matters: a small
number of shapes, each with one place it lives and one form it takes, and gates
that refuse the edits that break them. Give the practice a structure and the
discipline stops being something you have to remember to have.

That reading also settles a question a fresh reader raised twice: whether this is
for software. None of the rules names code, so the answer is that the domain is
irrelevant, and the page has to say it outright rather than let a week of
tech-flavoured examples answer it by implication.
