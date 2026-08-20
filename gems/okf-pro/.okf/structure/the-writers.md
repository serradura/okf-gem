---
type: Component
title: The writers — pure transforms, a declared delta, and the refusal that enforces it
description: Every write verb computes its new text without touching the disk, declares the lines it means to add, remove and move, and is refused if the actual delta differs.
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The files

| file | pure? | what it owns |
|---|---|---|
| `lib/okf/pro/conserve.rb` | pure | the write contract, enforced: line multisets in, refusals out |
| `lib/okf/pro/board/edit.rb` | pure | the board's text transforms, and the keyed selectors |
| `lib/okf/pro/log/edit.rb` | pure | a dated line, under its day, newest-first |
| `lib/okf/pro/writes.rb` | shell | the mechanical writers: read, transform, guard, rename |

# The shape every verb has

Read the file. Compute the new text with a **pure** transform — `Board::Edit` and
`Log::Edit` cannot touch the disk, which is what makes the transform testable
without a fixture and unable to half-write. Declare the delta: which lines were
added, removed, moved. Then `Conserve.check` compares the declared delta against
the actual one and refuses with exit 2 — **nothing written** — if they differ in
either direction.

That is the enforcement of [derivation-that-writes](/design/derivation-that-writes.md):
a write verb is additive and targeted, never regenerative. `Conserve.normalize`
chomps, so a missing final newline is not a delta; `counts` and `subtract` do the
multiset arithmetic, so a line moved between sections is a move rather than a
delete plus an add.

# What the verbs are

`Writes` holds `capture`, `promote`, `demote`, `journal_open` and `close`, and
each one is a plan-then-commit pair: `plan` computes and conserves, `commit`
writes atomically. `PROMOTE_FROM` is the two sections a promotion may come from.
`dormancy_note` is what a demotion says.

`Board::Edit`'s selectors are the part worth reading before touching:
`select` tries `by_target` then `by_substring`, and reports `no_match` or
`ambiguous` rather than guessing. `BUDGET_LINE` is the header regex
`set_declared` rewrites, and `NAMES_NOTHING` is the pair of selectors that
address nothing at all — an empty string and a bare `/projects`.

# Three refusals that are not politeness

* **A missing file is refused, never created.** `capture` will not create
  `board.md`; `journal open` will not create `journal/index.md`. An index
  rebuilt from the one line a verb knows is regeneration wearing an append's
  clothes.
* **Text spanning lines is refused, not escaped.** Agent text reaches a board
  line body or a journal entry body and nowhere else.
* **A caller-supplied name is contained twice** — one directory segment, *and*
  resolving inside the bundle, because `projects/<slug>` can be a symlink out.
  `contained?`, `escaping` and `escape_refusal` are that check; the directions
  are argued in [containment-directions](/contract/containment-directions.md).

No verb writes a concept body or sets `verified:`.
