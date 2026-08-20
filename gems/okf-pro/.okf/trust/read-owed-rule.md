---
type: Decision
title: A briefing is owed a read until a human has verified it
description: §5.3's trust tiers replaced a truthiness test on `verified`, and the four call sites that read the rule have to move together or a briefing falls through all of them.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The rule

```ruby
awaiting_read?  # declared_generated? && trust_tier != :human_reviewed
owner_read?     # trust_tier == :human_reviewed
```

`declared_generated?` is raw-key detection, so it separates hand-written (no
provenance at all) from v0.1-with-a-`timestamp`, which the old
`frontmatter["generated"]` test conflated with okf's own fallback.
`trust_tier` reads §5.3: no `verified` is unverified, a `process:` or agent
actor is machine-confirmed, a `human:<id>` actor is human-reviewed.

# Why all four sites move together

Two of them are exact opposites: `unverified_ids` says *the board still owes
this a To-read line*, `verified_reference_targets` says *the line can go*. Two
more read the same rule for different audiences: `Attestation.report`
corpus-wide, and the snapshot's `unverified briefings` counter.

Testing `verified` for truthiness made a nightly `process:`-verified briefing
simultaneously **awaiting the owner's read** to one caller and **verified, drop
the line** to the other. The board line vanished, and the read was never owed to
anyone again. Moving one site and not the other manufactures exactly that state,
which is why the rule is stated once, in one comment, over both predicates.

# What changed for an adopting bundle

`Snapshot.counters["unverified briefings"]` changes meaning, and the stop gate
verifies that counter field by field — so every log line in a bundle written
against the old rule goes stale on upgrade. That is a migration note, not a bug:
the counter is now answering a better question.

# The general shape

When a derived value is read by several call sites and each re-derives it from
raw fields, the sites do not drift *gradually*. They diverge the first time the
underlying vocabulary gains a case none of them was written for — and the divergence
is silent, because each site is individually correct about the field it reads.
