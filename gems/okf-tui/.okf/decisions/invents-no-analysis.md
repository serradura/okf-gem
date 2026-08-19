---
type: Decision
title: It Invents No Analysis
description: Every judgement on screen is a pure call into okf; the TUI adds no check, score, or verdict of its own, which bounds what a feature request may be answered with.
tags: [okf-coupling, dependencies]
generated:
  by: human:maintainer
  at: 2026-07-19
sources:
  - title: "`lib/okf/tui.rb` — the module comment stating the split."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/lib/okf/tui.rb
  - title: "`lib/okf/tui/model.rb`, `lib/okf/tui/workspace.rb` — every analysis is a memoized call into okf."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/lib/okf/tui/model.rb
---

# Overview

`OKF::Bundle::Reader` and `OKF::Registry` are the only parts that touch disk, and
everything drawn is a pure call on the resulting in-memory bundles — `catalog`,
`graph`, `validate`, `lint`, `Bundle::Search`. The TUI is one more shell over the
same core the `okf` CLI and the graph server already use.

The rule this actually imposes is a *negative* one, and it is the reason to write
it down: **a question the TUI cannot answer by asking okf is a question it does
not answer.** No extra lint check, no derived score, no "helpful" verdict
computed locally. If a screen wants an analysis okf does not expose, the change
belongs in okf.

# What that keeps intact

okf's own contracts survive the port to a screen, rather than being softened for
presentation:

| okf contract | How the screen keeps it |
|--------------|------------------------|
| `validate` and `lint` answer different questions | separate sections in the health view, never merged into one score |
| reads are best-effort | an unreadable file reports as `⊘ n unreadable`, not fatal |
| exit codes mean something | a bad directory exits `2`, the usage-error code |

The one place the TUI *does* add vocabulary is presentational: the clean /
warnings / not-conformant verdict that colours the bundle name everywhere it
appears. That is a rendering of `validate` + `lint` output, not a fourth
judgement — see [status-vocabulary](/rendering/status-vocabulary.md).

# The cost

It makes okf-tui's release calendar depend on okf's. The search view demonstrated
the sharp edge: [search-facade-coupling](/decisions/search-facade-coupling.md)
was blocked entirely on an okf release, with no local workaround *by
construction* — implementing a fallback search here would have broken this rule.

That one has since resolved (okf 1.9.0 shipped the facade), which is the point
rather than a footnote: the cost of this rule is paid in **waiting**, not in
capability. The wait ended, and nothing had to be built twice.
