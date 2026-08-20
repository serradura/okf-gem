---
type: Decision
title: One door per sibling
description: okf-mcp, okf-tui and okf-pro ship no executable and arrive as an `okf` verb through the plugin seam — a name not installed is a name that cannot drift, and for one of them it is a safety property.
tags: [cli, plugin, distribution, entry-point]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: gems/okf-tui/AGENTS.md
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/AGENTS.md
  - title: gems/okf-pro/AGENTS.md
    resource: https://github.com/serradura/okf/blob/main/gems/okf-pro/AGENTS.md
---

# The decision

Only the kernel ships an executable. `okf mcp`, `okf tui` and `okf pro` are
verbs registered through [the extension seam](../design/extension-points.md);
none of the three has an `exe/`.

okf-tui had one — `exe/okf-tui`, which did nothing but call the same
`CLI.run` — and it went before the first release, while removing a name still
cost nobody anything.

# What it buys

**One name to install, document and keep working.** A second binary that only
aliases a verb is a second entry in every README, a second thing to keep on
`PATH`, and a second argument grammar free to drift from the first.

**One resolution seam.** A verb inherits the kernel's ref grammar, so `@slug`, a
bare `@`, `@group` and the refusal of `@all` mean the same thing everywhere,
including the messages and the exit codes. A separate binary would have to
either share that by coupling or reimplement it — and reimplementing it is how
two surfaces come to disagree about what a bundle is called.

# For okf-pro it is not tidiness

Its scaffold writes a shell wrapper that dispatches to **one** absolute `okf`
resolved from `PATH`, and refuses unless that binary identifies itself as the
enforcer. A stray `okf` on `PATH` that exits 0 is indistinguishable from a clean
gate by status alone — which is a gate silently switched off.

A second entry point would be a second thing for that wrapper to recognise, on
the one code path where being wrong means an unchecked edit is waved through.

# The cost, and what would reverse it

A user who does not know the plugin seam exists cannot guess that installing
`okf-tui` gives them `okf tui` rather than `okf-tui`. `okf help` prints
installed extensions under their own heading for exactly that reason.

Adding a binary back needs an argument stronger than symmetry with other gems.
