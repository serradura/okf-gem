---
type: Learning
title: The bundle fixture is a client of the code under test
description: The bundle fixture computes its own snapshot line by calling the code under test, so a change to the counters reaches every fixture carrying a log day — which bounds what a green ported suite proves.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# Why it calls the code

The fixture writes a real bundle to a temp directory: real frontmatter, real
indexes, a real board. A mock would test the mock — the checks that matter most
consult the corpus through `okf validate`, `okf lint` and `okf search`, and none
of them can be exercised against a stub without exercising the stub instead.

The log day goes further and computes its snapshot line with `Snapshot.line`,
deliberately: the stop gate verifies counters field by field, and a fixture
carrying a hand-typed line would drift from its own board exactly the way a
person's does. Tests *about* drift write their wrong line directly.

# What that costs

It makes the fixture a client. A change to the counters, or to what
[the read-owed rule](/trust/read-owed-rule.md) counts, reaches every fixture with
a log day — in the same step where a ported suite running green is supposed to be
independent proof that the port preserved behaviour.

So "the suite is green, therefore nothing changed" is only true for changes that
do not touch what the fixture calls. Where a work item does touch it, the
expected drift is stated in advance and the fixtures are updated as part of that
item — not discovered afterwards and patched until the suite agrees with itself.

# The general shape

A fixture that computes rather than states is more honest and less independent.
Both halves are real, and the useful discipline is knowing which changes cross
the line — not choosing one side permanently.
