---
type: Learning
title: Existence is not identity
description: A stray `okf` on PATH that exits 0 passes every gate, and no exit-code normalisation can tell it from a clean check.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The claim that was wrong

"Normalise the exit codes — map anything that is not 0 or 2 to 2 — and the stray
binary is handled."

It is not. A shim that exits **0** maps to 0. Every gate is off, silently, and
the status carries no evidence either way: a clean check and a program that did
nothing produce the same byte.

# What replaced it

`okf pro hook` writes `okf-pro-enforcer v1` to stderr as the first act of
every check, and the wrapper refuses unless it sees that line. Costs one process
and 0.16 s against 0.14 s for a bare normalised wrapper.

The earlier design was a **handshake** — a second invocation, `okf pro
contract`, answering the same string. It proved less at twice the cost: the
handshake passed while the library was missing, because answering a question is
not the same as reaching a check. The marker is emitted at the point where
dispatch has already committed to running one, so its presence means the check
was reached, not merely that the plugin loaded.

# The door that had the argument written down and not applied

The commit hook asked `command -v okf` and then trusted the exit status — the
exact claim the section above calls wrong, at the one door that exists for the
edit the agent hooks never see. A `#!/bin/sh\nexit 0` shim named `okf` made
`okf pro records` and `okf pro audit` both pass, and the commit went through
with nothing checked and nothing said.

It proves identity the same way now, and it has to borrow the hook door to do
it: the marker is written by `okf pro hook`, before a check runs, and the CI
verbs do not emit it. So the handshake runs a real gate — `okf pro hook
guard-verified` on an empty event, which reaches the check and gives it nothing
to say — and requires the marker on stderr. Borrowing the door is the point:
identity is proved by *reaching a check*, which is what the retired `okf pro
contract` handshake could not do.

The general form is worth stating, because this door had the reasoning
available and did not apply it: **a defence written in one file is not a
defence of the system.** Three doors exist precisely because each sees what the
others cannot, so a proof that only one of them makes is a proof with a hole
the shape of the other two.

The check itself is [the wrapper's](/seam/the-wrapper.md), for the same reason
everything else there is: it has to happen before the program being identified
gets to answer for itself.

# What it does not defend against

A shim that deliberately prints the marker. That is a forgery, and no wrapper
defends against one — the threat model here is a leaked variable, a stale shim,
a half-installed gem. Claiming more would be the false confidence that is worse
than no rule.

# The general shape

When a check's "pass" and a check's "absence" produce the same observable, no
amount of interpreting that observable will separate them. A second, orthogonal
observable has to exist — and it has to be emitted from the point that proves
what you actually want proven.
