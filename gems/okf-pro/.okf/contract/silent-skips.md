---
type: Finding
title: The checker broke its own third clause
description: A default Linter.call skips two clock-gated checks and still reports healthy, so the gate reported clean over checks it never ran.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# What was measured

On this gem's own gate path, before the fix:

```
skipped_checks on the gate path: [:expired, :stale]
healthy? true
```

`Bundle::Linter.call(bundle)` with no options cannot run `expired` (it has no
clock) or `stale` (it has no cutoff). Seven of the nine blocking checks ran, the
gate reported clean, and nothing said so — [the third clause](/contract/the-contract.md)
broken by the checker itself, in the one place nobody can notice.

okf 2.0 confesses it in `stats[:skipped_checks]`, a field added for a reader
exactly like this one. The gate discarded it.

# Why relaying the confession is not the fix

The obvious repair — return the confession as a refusal — makes the gate block
every edit in every bundle until someone supplies a cutoff. A gate that refuses
constantly is a gate switched off within a day, which is the same outcome by a
slower route.

The fix is to leave nothing skipped:

* `today:` is supplied, so `expired` runs. It is `:info`, so this adds no
  refusal — it removes a silence.
* `stale` is excluded **in source**, with the reason beside it: it asks
  "untouched since when?", and this gem has no cutoff policy and no business
  inventing one. An excluded check is the opposite of a silently skipped one.

`skipped_checks` is then empty in normal operation, which turns the confession
into a live guard rather than a formality: the day okf adds a third clock-gated
check, this gate reports it instead of quietly not running it.

# The general shape

A field that reports what did not happen is worthless to a consumer that
discards it. When a dependency offers one, the question is not whether to log
it — it is what state makes it non-empty, and whether that state is one the
caller can act on.

# The same shape, at three more doors

All three were found the same way and are the same failure: a checker
reporting clean over something it had not looked at.

**The CI door dropped half of what the validator said.** `Audit.conformance`
returned early on `valid?`, so `result.warnings` went in the bin while the hook
door reported them at length. A scalar `verified: human:rod` is *conformant* —
so the attestation guard asks, the owner approves, the reader then drops the
malformed value, and the trust tier stays `unverified` forever. Caught at the
agent's tool boundary and waved through by CI and by `pre-commit`, which are the
two doors an edit made in an **editor** actually passes. Two doors asking one
question may not answer differently about one bundle; the severity was never the
disagreement, the silence was.

**A whitelist fails open on every letter it does not name.** The append-only gate
asked git for `--diff-filter=MDR`. Replacing a committed past day with a symlink
stages as `T`, a typechange — not `M`, not `D` — so the gate reported
"append-only" and the commit destroyed the one artefact nobody can reconstruct.
A whitelist's default answer for anything unenumerated is *pass*, which makes the
set something to justify rather than inherit: `MDRT`, with the reason beside it.

**And the clause above was kept at one door and broken at the other.** The whole
argument at the top of this page — supply the clock, exclude `stale` in source,
assert the residue — was applied to the hook door and never to `okf pro audit`,
which called `Linter.call(bundle)` bare and printed `clean.` over `expired` and
`stale`. A lesson recorded against one call site is not a lesson applied; when
this page said "the gate", there were three of them, and the fix has to be asked
of each. The residue is now asserted at both.
