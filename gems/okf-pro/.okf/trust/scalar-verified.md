---
type: Finding
title: A scalar `verified:` fails in the worst available direction
description: The guard fires on the word, the owner approves, and then the reader drops the malformed value — so the concept stays unverified and the To-read line is demanded forever.
---

# The sequence

```yaml
verified: human:rod        # a scalar; §5.2 wants a mapping or a list of them
```

1. `Guards.attests?` matches on the word `verified:` and routes the write to the
   owner for approval. It is deliberately generous — this gate **asks**, so a
   false positive costs one prompt and a miss costs a forged signature.
2. The owner approves. From their side, the attestation happened.
3. `Concept#verified` drops the entry, because it is not a mapping. The tier
   stays `:unverified`.
4. The To-read line is demanded forever, and the owner is told repeatedly to
   read something they already read and signed.

# The fix is one line, in the right place

`okf validate` already says exactly what is wrong — *verified should be a
mapping or a list of mappings* — as a **warning**, because §9 forbids the
validator from rejecting a soft problem. `Conformance.check` read
`result.errors` only, and dropped every warning on the floor.

Surfacing `result.warnings` fixes the whole class. The alternative — a
check of our own for the trust family's grammar — would be a second parser to
keep in step with okf's, which is how the two spellings of one rule start
disagreeing.

They are surfaced as advice, not as errors: §9's separation between conformance
and curation is the kernel's, and a gate that promoted the validator's warnings
would be overruling it from outside.

It is the same failure class as [the skipped checks](/contract/silent-skips.md)
and for the same reason: a report that says "fine" over a question nobody
answered. And it lands on [the read-owed rule](/trust/read-owed-rule.md), which
is where being wrong costs the owner a demand they already discharged.

# The general shape

The most dangerous validation failure is not the one that rejects. It is the one
where a permissive *detector* and a strict *parser* disagree — the detector
fires, a human confirms, and the parser discards. Everyone downstream then has
positive evidence that the thing happened, and the stored state says it did not.
