---
type: Constraint
title: A layout that cannot fit says so
description: Health is two panes above 112 columns and one at a time below it, reached by the same key either way — a narrow terminal changes what is shown rather than silently clipping it, and a new split is judged by its narrowest column.
tags: [rendering, layout, terminal, width]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
---

# The rule

A pane that cannot fit its content does not clip it. It stops claiming to show
both halves.

The health view is the instance: two panes above 112 columns, one pane at a time
below it, and the **same `Tab`** reaches the other one in both modes. The key
keeps its meaning across the breakpoint, so nothing a reader has learned stops
working when they narrow the window — the mode changes, the vocabulary does not.

# How to judge a new split

By what its *narrowest* column does to the longest row it must carry, not by how
it looks at the width you happen to be developing at.

Health passes that test by construction rather than by tuning: its right pane
holds a fixed width because every row in it is short by design, and every row
that carries a path — the ones with no bound on their length — is on the left.
A split that puts an unbounded row in a fixed column has already failed, and
will fail invisibly, because at a comfortable width it looks correct.

This is the layout-level form of the same discipline
[width measurement](ansi-aware-width.md) applies at the character level: a frame
is only correct if it is correct at the width it was not designed for.
