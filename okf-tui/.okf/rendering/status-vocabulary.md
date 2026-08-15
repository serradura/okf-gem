---
type: Concept
title: One Verdict, Worn Everywhere
description: A bundle is clean, warned, or not conformant, and that single judgement drives its colour in every place it is named — so a problem is visible without opening the health view.
tags: [rendering, ux]
timestamp: 2026-07-18
---

# Overview

`validate` and `lint` answer different questions and the health view keeps them
in separate sections, as [okf requires](/decisions/invents-no-analysis.md). But a
*reader* needs one thing at a glance: is this bundle all right?

So the two outputs collapse into one presentational verdict:

| Verdict | Source | Colour |
|---------|--------|--------|
| not conformant | `validate` has §9 errors | red |
| warnings | `validate` is clean, `lint` has findings | orange |
| clean | both clean | default |

This is a *rendering* of okf's analysis, not a fourth judgement — no check is
computed here.

# Why it appears everywhere

The verdict follows the bundle's name into every place the name appears: the
header, the footer badge, its row in the registry list, its detail pane, and the
health tab's own label.

The health tab carrying it is the point of the design. Without it a reader has to
*visit* the health view to learn there is anything to see, which means the
common case — nothing wrong — costs a trip, and the uncommon case is invisible
until you happen to look. Colouring the tab makes the bundle's state ambient:
you find out from wherever you already are.

Because the colour is attached to the name rather than to a view, switching the
active bundle changes it everywhere at once, which is what makes it readable
while moving between bundles — see
[cross-bundle-scope](/interaction/cross-bundle-scope.md).

# Citations

[1] `lib/okf/tui/views.rb` — `health_status`, `STATUS`, `status_style`.
