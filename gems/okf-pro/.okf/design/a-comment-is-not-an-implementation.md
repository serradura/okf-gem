---
type: Learning
title: A comment is not an implementation
description: A regex that claimed to anchor `>` to a redirection position never did, and the guard it powered fired on reads for its whole life — which is the shape of noise that retires a gate. The same class reaches comments, docstrings and the bundle's own concepts.
---

# What happened

`ShellGuard::MUTATORS` matched a redirection with `>{1,2}[[:blank:]]*[^|&\s]`,
and the comment above it said, in as many words, that `>` "is matched only
where a redirection can sit, so `a > b` in a comparison inside a command is not
automatically a write."

Nothing in the pattern implemented that. There was no lookbehind, no anchor, no
position test of any kind — the claim was true of the sentence and false of the
code, and it had been for the regex's whole life.

In this bundle that is the worst possible miss. `-->` closes the HTML comment
the skill mandates on every keyed rule and is also mermaid's edge; `=>` is in
every quoted Ruby hash. So `grep -rn "a --> b" .okf/` — a **read** — was routed
to the owner as a suspected write, and so was every grep for a rule marker.

# Why that is worse than a gate that is simply absent

The guard's honest verdict is *ask*: it cannot parse shell, so it routes the
decision to a person who can read the command. That verdict is only worth
anything while the prompts are rare enough to be read. A guard that fires on
reads produces a stream of prompts whose correct answer is always "approve",
and the reflex it trains is approval without reading — which is precisely the
state where the one prompt that mattered gets approved too.

So the cost is not the false positives. It is that the true positive stops
being distinguishable from them, and the gate has been retired without anyone
deciding to retire it. That is failure mode 1 wearing the checker's uniform,
the same shape [silent-skips](/contract/silent-skips.md) records from the other
direction.

# The rule

**A comment describing a property the code does not have is worse than no
comment**, because it is what a reviewer reads instead of the code. Two things
follow, and both are cheap:

* When a comment asserts a *property* — anchored, bounded, ordered, exhaustive
  — the test file for that unit must contain the case the property forbids. The
  arrow cases were unwritable as long as the property was only claimed; writing
  them is what made the gap visible in one run.
* When a guard exists to route a decision to a person, its false-positive rate
  is part of its correctness, not a matter of taste. `test_ascii_arrows_are_not_redirections`
  exists at the same rank as the drills that prove a refusal, because a guard
  people switch off refuses nothing at all.

# The same class, at four distances

The regex is the sharpest instance and not the only one. Ordered by how far the
prose sits from the code it misdescribes:

* **Beside it.** `Board::Edit.set_declared` found the budget header *per line*
  and put it back with `String#sub`, which searches the whole text — so any
  earlier line whose tail happened to equal the header matched first, the prose
  was rewritten and the header left stale. `Conserve` caught the mismatch and
  refused, which is the system working; but the refusal **named the prose line**,
  and the board stayed unpromotable until somebody edited a line that was never
  the problem. A lookup and its inverse have to agree on their unit, and a
  refusal is only as useful as the thing it points at.
* **Two definitions away.** `Friction`'s paragraph about reading a class out of
  a shell command sat above `clear`, fused with `clear`'s own comment, two
  definitions from `classify_command`. Nothing is wrong with either method; a
  reader arrives at the wrong one holding the right explanation.
* **In a message the reader acts on.** The writers share one missing-argument
  message, and `close` does not take what it offers: a project is one directory
  segment, so "a substring only one board line carries" is a refusal, and so
  was `/projects/<slug>/index.md` — the exact link a board line carries and
  `okf pro board` prints. A message naming what the verb rejects is worse than
  no message, for the same reason a wrong comment is: it is what the reader
  acts on instead of the code. Fixed from both ends — the message names one
  directory segment, and `close` now accepts the third spelling
  `Board::Edit.by_target` already treated as the same commitment.
* **In the bundle.** [telemetry-does-not-lie](/contract/telemetry-does-not-lie.md)
  described a recorder watching three paths while the code watched one — and
  went into the tree that way *in the same commit as the code*, which is the
  commit rule in `AGENTS.md` doing the opposite of its job. A concept has a wider readership
  than a comment and is trusted further, so this is the same failure with the
  blast radius turned up. Maintaining `.okf/` in the same commit means checking
  it against the diff, not merely editing it in the same breath.
