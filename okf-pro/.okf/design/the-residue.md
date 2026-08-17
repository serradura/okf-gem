---
type: Learning
title: The residue
description: Trust measures process, never truth — a misheard number, sourced and verified, reaches maximum trust while being false, and no law closes it.
---

# The limit

`generated:` and `verified:` say how a claim arrived, who looked at it, and when
it expires. They never say that it is true. Mishear a number, capture it,
source it perfectly, read it yourself and attest to it, and the concept reaches
the top trust tier carrying a false claim — faithfully, exactly as designed.

This is not a gap to be closed in a later version. It is the ceiling on what any
provenance system can promise, and it is stated on every tier of the design
rather than buried, because a design that implies otherwise is more dangerous
than one that says so plainly. A reader who believes the tiers measure truth
will stop checking; a reader who knows they measure process keeps checking, which
is the behaviour the whole apparatus is trying to preserve.

A passport proves who issued it, when, and that the process was followed. It
cannot prove the bearer is a good person. Nothing in this design is a lie
detector.

# What the mitigation actually buys

The source pointer. Not truth — **falsifiability**. A claim that names where it
came from can be checked later by someone who doubts it, and everything derived
from it can be found and re-examined when it turns out to be wrong. A claim with
no pointer cannot be reconciled at all, which is why the pointer is also
[Law 1](/design/three-laws.md)'s precondition and not merely good manners.

So the honest promise is: a well-sourced mistake stays catchable. That is the
best a knowledge system can offer, and anything promising more is selling
something.

# Why the trust tiers are read off the actor, not off truthiness

The vocabulary that carries this is v0.2's — a `verified` entry by a `human:`
actor makes a concept human-reviewed, anything else machine-confirmed, no entry
at all unverified ([trust/read-owed-rule](/trust/read-owed-rule.md)). The tiers
describe *who performed which process*, which is exactly the claim the design
can support. A tier that meant "checked and correct" would be the residue
denied.
