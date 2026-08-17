---
type: Overview
title: Corpus
description: The standard this knowledge base is kept at — the naming policy, ownership of the staleness windows, and the limit reconciliation runs against.
---

# The standard

Every adopter has exactly one area on day one: tending the thing they are
reading right now. It has no done. It has a level, and the level is this — **a
claim in here can be found by someone who does not already know it is here,
and does not sit next to its own contradiction.**

This file holds the standard, never the state. Counts live in
[log.md](/log.md); open work lives on [board.md](/board.md). If you find
yourself updating this file daily, something that belongs on the board has
leaked into it.

# Reconciliation

The discipline itself is operative as Rule 1 of the okf-pro skill, which
every bundle-touching session loads: search before filing, read bodies rather
than titles, deprecate the loser at ingestion, and send what cannot be settled
to [board.md](/board.md) as one dated conflict line.

One operative copy, and it is not this one — this area holds the standard that
rule serves, and the rule's limit: it catches collisions as well as the search
vocabulary does, and no better. That limit is what makes the next section
load-bearing rather than cosmetic.

# Naming policy

* **Never name a concept, tag, or type after something that already means
  three things in your domain.** A file called `status.md` in a bundle where
  "status" is a ticket field, a deploy state, and a weekly email is a file
  nobody can search for.
* Prefer the phrase you would actually say out loud to a colleague. The search
  that matters is the one made by someone who has forgotten the filing.
* Types are a small vocabulary, added to reluctantly: Briefing, Decision,
  Finding, Learning, Term, Journal Entry, Transcript, Overview, Board. A tenth
  type needs a reason that survives being said aloud.
* [glossary/](/glossary/) is where a contested word goes to get one meaning.
  When two concepts disagree because they are using a word differently, the
  fix is usually a Term, not an argument.
* **A directory is a retrieval question, and a room pays rent by answering one
  no other room answers.** The five here are the starting set rather than the
  closed set — but a sixth is earned by an incident, never anticipated. What is
  forbidden is the *catch-all*: a room meaning "everything else" is a blind spot
  by construction, because things enter it and nothing enumerates them again,
  and nobody has ever searched for the thing that did not fit. That is also why
  this bundle splits what PARA keeps as one Resources room into
  [reference/](/reference/), [learnings/](/learnings/) and
  [glossary/](/glossary/): three questions, asked at three different moments.

# Staleness

This area **owns** the staleness table — deciding what decays, and how fast.
The table itself lives in the okf-pro skill
(`.claude/skills/okf-pro/SKILL.md`), next to the frontmatter policy it
governs, because one operative copy beats two agreeing copies until the day
they stop agreeing.

Ownership means: when a window proves wrong in use — briefings going stale
while still accurate, terms rotting before their date — the number changes
here first as a decision, then in the skill as the rule, and the change gets a
[log.md](/log.md) line.

`stale_after:` reports; it never gates. A date that has passed is a prompt to
look, not a verdict that the concept is wrong. Where the boundary falls is the
format's to say and not this bundle's: a concept is stale when the day has
arrived, inclusive, and `okf lint --only expired` is what answers the
question. A second implementation of it that disagreed by a day would be worse
than none.
