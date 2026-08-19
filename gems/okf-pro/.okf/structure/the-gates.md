---
type: Component
title: The gates — one question each, and the two doors that ask them all
description: Nine files, each answering one invariant, plus `audit` (the CI door) and `state` (the readers' payload) which ask the same questions from a different side.
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The files

| file | the law or the question |
|---|---|
| `lib/okf/pro/reconcile.rb` | **Law 1** — what already says this, while the write is still hot |
| `lib/okf/pro/budget.rb` | **Law 3** — the cap, and the dormancy question |
| `lib/okf/pro/closing.rb` | **Law 2** — the stop gate, and the session banner |
| `lib/okf/pro/snapshot.rb` | Law 2's counters, derived — a checker, never a generator |
| `lib/okf/pro/attestation.rb` | what still awaits the owner's read |
| `lib/okf/pro/pairing.rb` | the board↔work invariants, both directions |
| `lib/okf/pro/conformance.rb` | `okf validate` + `okf lint`, in process |
| `lib/okf/pro/audit.rb` | the CI door: the same invariants minus the tool event |
| `lib/okf/pro/state.rb` | the readers' payload — cheap by contract |

The laws themselves are [design/three-laws](/design/three-laws.md); this concept
is where each one is implemented.

# Snapshot is a checker, not a generator

`Snapshot.counters` recomputes every number from the board and the bundle;
`Snapshot.line` renders it; `Snapshot.parse` reads a line already written; and
`Snapshot.verify` compares the two and reports the difference. There is no
`--write`, and there deliberately never will be: a writer and a checker sharing
a code path agree trivially, which is exactly what Law 2's confession must not
be able to do.

# Conformance is the kernel's answer, not a second one

`Conformance.check` runs the kernel's validator and linter in process against
the target's bundle. Every conformance and curation question is okf's to answer
— this gem owns the policy on top. The one rule it adds is the contract's third
clause: `Linter.call` with no options skips `expired` and `stale` and still
reports `healthy?`, so `confession` surfaces what was not run rather than
reporting clean over a silent skip.

# Two doors, one set of invariants

`Audit.call` is the CI door. It asks `structure`, `conformance`, `curation`,
`snapshot` and `pairing` of a tree with no tool event in sight, and it reserves
exit 1 for *findings* — spelling "the checker broke" as 2, because a pipeline
that cannot tell those apart learns to ignore both. `ambiguous_layout` is its
refusal when it cannot tell which bundle it was pointed at.

`State.call` is the other side: what is on the board, in one call, cheap by
contract. `full: true` is the one parse it will pay for — the readers exist
because an agent working in a seeded bundle rediscovered the board by reading
raw markdown while the stop gate was already computing it.

# Pairing holds the one git shell-out

`Pairing.failures` asks both directions at once: a project with no board line,
a board line with no project, a target that does not resolve, a link to a
closed project, a read line gone stale. `MARKER` and `NEGATED` are a pair — the
second is why "never closed" is not read as a closure marker. `dirty_markdown?`
is the git shell-out, and it is the only one outside `records.rb`.
