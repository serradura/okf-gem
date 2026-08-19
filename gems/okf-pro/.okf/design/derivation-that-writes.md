---
type: Decision
title: Derivation may write, under a conservation guard
description: Failure mode 07 forbids an LLM regenerating a view; it does not forbid a Ruby function performing a declared, line-conserving edit — and the status quo it was written against was the failure mode itself.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The verdict, read precisely

Failure mode 07 — **Agent Drift** — is stated in the lineage's design record as:

> An LLM regenerating a view drops a task, silently — no error, no diff anyone
> reads, one commitment gone. Closed by: the split. Derivation exists as a
> checker and never as a generator: a thing that computes and refuses has no
> way to drop anything in silence.

[snapshot](/design/three-laws.md) is built on that, and it stands: `okf pro
snapshot` computes the day's line and prints it, and the stop gate verifies the
line a person appended. Nothing writes it.

But the verdict names two things — **derivation** (recomputing a whole view and
writing it back) and **an LLM** (the actor). Neither is what a mechanical writer
does, and reading the rule as "no verb may ever write" left the status quo in
place: the agent rewrote `board.md` with a shell heredoc. That is the
silent-drop hazard exactly, performed by exactly the actor the record names. The
prohibition was protecting the failure mode rather than the bundle.

# What the write verbs may do, and what makes it enforceable

> **Additive and targeted, never regenerative.** A write verb may append a line
> or edit the line it was given. No verb rewrites a file it did not fully derive
> from that file's own prior contents. A writer never satisfies its own gate.

That sentence is a promise, and a promise is what mode 07 already broke once.
`Conserve` is what converts it into a property: every write verb computes its
new text purely, **declares the delta it intends** — added, removed, moved —
and hands before, after and claim to a guard that compares line multisets. If
the actual delta is not the declared one, the verb exits 2 and the file is
untouched.

The asymmetry matters in both directions. A line added that nobody claimed is a
finding; so is a claimed addition that never happened, because an edit that did
less than it said is how a promotion silently no-ops and reports success.

A Ruby function that provably cannot drop a line is the remedy for a heredoc
that can, and the difference between them is that this one is checked.

# What the guard cannot supply, and what it cannot see

**A satisfied checker is not a correct edit.** `close` marks a project index by
appending the closure marker to its first line, and guarded that by asking
whether the result satisfied `Pairing::MARKER`. It did — for a file whose first
line is `---`. `Pairing.marker?("--- — closed 2026-08-17")` is true, because
the regex needs only the word and a date. So an index carrying YAML frontmatter
had its fence destroyed, the concept silently lost its `type`, `title` and
`description`, and `okf validate` still exited 0. `Conserve` could not see it
either: the mangling *was* the declared edit.

The fix is to check the SHAPE of the line being edited, not only the shape of
the result: the first line must be a markdown heading, because that is where
the skill teaches the marker and the only place `closed?` looks. The general
form of the lesson is that a conservation guard proves a line was not dropped
and proves nothing about whether the right line was chosen — the choice needs
its own precondition.

**Decide about every file before writing any of them.** `close` touches three,
and `write_atomically` makes each write atomic and the set not. Checking as it
went produced a real half-closed bundle: a board that had lost its budget
header refused at step two with the index already marked, so the project read
as closed while its board line survived and no log entry existed — and the
refusal message said nothing had happened. Every check now runs and every new
text is computed before anything lands, so a *refusal* writes nothing at all,
which is what the message claims. The residue of a crash mid-sequence is still
real, and still visible to `okf pro audit`; the residue of a refusal is now
none.

**A verb that turns a name into a path owes a containment decision — twice.**
`File.join` resolves `..` without comment, so `okf pro close ../../somewhere`
would put a closure marker on a stranger's index. A project is one directory
segment by the structure's own rule, so anything else is refused rather than
normalised — quietly rewriting a path the caller gave is how a traversal
becomes an edit nobody sees.

A validated name is not a contained path, though, and the second half was
missing: `projects/<slug>` can be a **symlink** out of the bundle, and `close`
read and rewrote it with the uncontained pair while `Pairing.closed?` refused to
read the very same file and answered *open*. The write landed outside the bundle
and the checker then denied it had happened.
[containment-directions](/contract/containment-directions.md) carries the rule
that came out of it: the read door and the write door are two decisions about
one path, and they must agree.

**The guard's refusal is only as good as the line it names.** `set_declared`
found the budget header per line and spliced it back per substring, so a prose
line quoting the header was rewritten instead. `Conserve` saw the delta was not
the declared one and wrote nothing, exactly as designed — and then named the
prose line, leaving the board unpromotable until somebody edited text that was
never at fault. A guard that refuses correctly and points somewhere useless is
still a verb the user cannot get past.

**A selector has to name a thing.** They are keyed and never positional, and
they refuse on ambiguity — but `select` only refuses on more than one match, so
a selector that matched *everything* still went through wherever exactly one
line was in range. `/` and `/projects` chomp to a prefix that is a proper
ancestor of every linked line, and `start_with?` turns the name into a wildcard;
the empty-selector guard had the argument written down and covered one spelling
of it. A directory every project sits under names none of them.

**And a writer's first positional is content, which makes a flag data.** The
write verbs take no flags, so `okf pro capture --help` appended
`- <date> — --help` to the Inbox and exited 0. A verb whose failure mode is
committing a garbage board line has to refuse a leading dash rather than
swallow it; `--` is the escape for the rare content that really does begin with
one.

# What still may not be written

* **A view regenerated from anything but its own prior contents.** The rule is
  the file's text in, the file's text out, plus a named delta.
* **`snapshot --write`.** A writer and a checker sharing a code path agree
  trivially and prove nothing; the stop gate keeps its independent read.
* **A concept body.** Prose is judgment, and judgment is the skill's. `close`
  performs its three mechanical moves and reports the durable extraction to
  `learnings/` as owed.
* **`verified:`.** The owner's approval is the attestation
  ([trust/read-owed-rule](/trust/read-owed-rule.md)); a verb that wrote it would
  be manufacturing the one thing the whole trust surface measures.
* **A seeded file that is missing.** `capture` will not create `board.md` — a
  board written by a verb is a board nobody decided the shape of — and the same
  answer holds for `journal/index.md`, which `journal open` appends a line to.
  Rebuilding it from the one line the verb knows how to write returns a file
  holding only that line: the `# Journal` heading and the seeded prose gone,
  under a message reporting success. That is regeneration wearing an append's
  clothes, and the giveaway is that the output does not depend on the input.
  The sibling policy is the rule: a write verb refuses a missing file and names
  the audit that reports it.

# The safety property the guards cannot supply

A verb invoked through Bash is seen by neither `guard-verified` (Edit and Write
only) nor `shell-guard` (there is no mutator pattern in `okf pro capture`). So
the write verbs are safe **by construction** rather than by being watched:
agent-supplied text reaches a board line body or a journal entry body and
nowhere else, and text spanning lines is refused rather than escaped — a
one-line write is a write that cannot carry a `---`.

The third piece is the one that only exists because a verb now takes a *name*
from the caller and turns it into a *path*. `okf pro close <slug>` marks a
file's first line, and `File.join` resolves `..` without comment — so a slug
that can leave `projects/` puts a closure marker on a stranger's index. A
project is one directory segment by the structure's own rule, so anything else
is **refused rather than normalised**. Quietly rewriting a path the caller gave
is how a traversal becomes an edit nobody sees, and it is the same instinct
[containment-directions](/contract/containment-directions.md) records for reads:
one decision per call site, made out loud.

The selectors carry the other half. They are keyed — a `/projects/<slug>` link,
or a substring only one line holds — and they **refuse on ambiguity** instead of
picking. A positional index is what
[structure-laws](/design/structure-laws.md)'s keyed-identity rule forbids, for
the reason this whole file is about: agents rewrite, and "the third line under
Backlog" names a different commitment after any edit anyone makes.
