---
type: Decision
title: Containment fails in four different directions, on purpose
description: A path that escapes the bundle is refused, or ignored, or read as "not closed" — and which one is right is decided per call site by what a wrong answer costs, at the write door as well as the read one.
---

# The rule

Every gate reads through `Pro.read_contained`, which resolves the path and
refuses one whose symlinks leave the bundle root. A `board.md` symlinked out is
not this bundle's board; a journal entry reached from outside is not this
bundle's record of a day.

That much is uniform. What happens *next* is not, and the divergence is the
decision worth recording — because "handle it consistently" is the instinct, and
here it would be wrong four times over.

# The four answers

| Site | On escape | Why that direction |
|---|---|---|
| `Target#read` | **raises** | The caller already proved the file exists, so an escape is a real containment failure. `CLI.run`'s dispatch rescue turns it into a refusal, which is the correct answer to something outside the bundle pretending to be inside it. |
| `Budget` (dormancy) | **reads as empty** | Dormancy is a question, not a gate. An unreadable entry means *no evidence of work*, which keeps the question being asked — the conservative direction for a prompt that costs nothing to answer. |
| `Pairing.closed?` | **reads as open** | A closure marker reached only through a symlink is not one anyone may rely on. Open is the safe answer: an open project keeps its board line, and a closed one loses it. |
| `Writes.close` (the marker) | **refuses** | The write door, and the same reasoning arrives at a refusal: a marker written outside the bundle is a stranger's file edited to satisfy a checker that will not read it back. |

Read the column right to left and the rule generalises: **pick the direction
that leaves the demand visible.** A refusal, a dormancy question and a retained
board line are all states a person will notice. Their opposites — a silent pass,
a project that stops being asked about, a board line quietly removed, a closure
marker on a file this bundle never reads — are all states nobody finds out
about.

# The read door and the write door are two decisions

The table above was written about reads, and that was the whole of the miss.
`Pairing.closed?` refused to read a project index reached through an escaping
symlink and answered *open*; `Writes.close` read and rewrote **the same path**
with the uncontained pair, `Pro.read_text` and `Scaffold.write_atomically`. So
`okf pro close escapee` put `— closed <date>` on somebody else's `index.md`,
exited 0, and left `okf pro audit` reporting the project as neither on the board
nor closed. Run twice it appended a second marker, so it was unbounded as well
as wrong.

Two things follow, and the second is the one worth carrying:

* **A containment decision belongs to a call site, not to a file.** The checker
  and the writer touch one path and are two sites; deciding once and assuming
  the other inherited it is how the strictest door and the loosest end up on
  the same `index.md`.
* **Contain the leaf, not the directory holding it.** The first fix asked the
  question of `projects/<slug>/`, which left the case one level down: an
  `index.md` symlinked out of a perfectly contained directory is read by
  `Pro.read_text`, which follows the link, and written back by `File.rename`,
  which does not — so the marker was computed from a stranger's title and
  landed as a real file *inside* the bundle, and the checker went on refusing
  to read the path it was written from. Containing the leaf covers both, since
  a directory that escapes takes every path under it with it.
* **Every file the verb writes, not the one the bug was reported against.**
  The leaf fix still only guarded `projects/<slug>/index.md`, and `board.md`,
  `log.md` and `journal/index.md` are rewritten by exactly the same read-and-
  rename pair: `okf pro capture` read a stranger's board through a link,
  appended a line and renamed a temp over it, so the link became a real file
  holding content the bundle never owned. A containment fix that stops at the
  path in the report is a fix for the report, not for the class — `Writes`
  now asks the question in one helper and every verb names the files it
  touches.
* **The two doors must agree about the same path.** They may reach different
  *answers* — the checker says open, the writer refuses — but those two are the
  same verdict seen from either side, and it is the direction that leaves the
  demand visible. A pair that disagrees is worse than either alone: the write
  lands and the check then denies it happened.

Nothing enforces the pairing. It is asked at review, the way this file's rule
already is, and the question is the same one: *what does this do when it cannot
answer?*

# Contain against the bundle, not against a root invented from the path

`Pairing.closed?` derived its root as `dirname(dirname(index_path))`, which is
`<bundle>/projects` — so `SafeRead` refused any project index whose realpath
left `projects/`, including one that never leaves the *bundle*. A project
legitimately archived behind a symlink (`projects/beta -> ../archive/beta`) read
as open forever, and the audit demanded a board line for work closed months ago.

The rule this page states is about **the bundle**, and every caller already held
it. A containment check that computes its own root is checking a boundary
nobody drew: it refuses inside the line it was meant to draw, and the direction
of that error is the one this page warns about from the other side — a demand
raised against a person who has already done the work is how a gate teaches
people to stop reading it.

# The one place it is deliberately absent

`BundleRoot.root_index?` has no root to contain against; it is the code
*deciding* what the root is. A raise there would be a permanent lockout, and a
rescue answering "not a root" would mis-root the bundle and disarm the journal
guard — so it reads plainly, and the comment there says why.

# Why `.scrub` is still ours

`SafeRead.read!` tags the encoding without validating it. One invalid byte
anywhere then raises out of the first regex that touches the string, and that
exception exits 1 — which the hook protocol reads as *proceed*
([exit-codes](/contract/exit-codes.md)). The scrub is not tidiness; it is the
difference between a gate that runs and a gate that lets the edit through while
appearing to have run.
