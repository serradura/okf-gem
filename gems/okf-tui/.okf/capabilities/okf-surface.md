---
type: Capability
title: The okf Surface This Gem Uses
description: Every kernel call the TUI makes, in one list — because the rule is that okf owns every judgement on screen, and a number this gem computed is a number that will disagree with `okf lint`.
tags: [okf, boundary, capabilities]
timestamp: 2026-08-19
---

# The rule first

**This program invents no analysis.** Everything on screen is a pure call on an
in-memory bundle the kernel built. The argument, and what it costs, is
[invents-no-analysis](/decisions/invents-no-analysis.md).

So this list is short on purpose, and the right instinct on finding it does not
cover your case is to ask whether the kernel should answer it — not to compute it
here.

# What is actually called

| kernel surface | reached through | shows up as |
|---|---|---|
| `Bundle` / reader | `Model#catalog` | every row in browse |
| `Bundle::Graph` | `Model#graph` | the graph view, `hubs`, `orphan_ids`, `edge_count` |
| `Bundle::Validator` | `Model#validation` | health's conformance findings |
| `Bundle::Linter` | `Model#lint`, `#skipped_checks` | health's curation findings, and the confession of what did not run |
| `Bundle::Search` | `Workspace#search` | the search view, across the whole scope |
| `Registry` | `Workspace` | the bundles view, and the only writes this gem makes |
| `CLI::Command` ref grammar | `Refs` | `@slug`, bare `@`, `@group`, and the refusal of `@all` |
| `Concept` trust/status | `Model#trust_posture`, `#status_posture` | the v0.2 chips and the one verdict |

Two of those are pinned against the CLI rather than trusted: the directory tree
is asserted against `okf dirs --json`, and the cohesion table against
`okf graph --traffic`, so the screen and the command cannot drift apart.

# The two probes

`OKF::TUI.search_capable?` and `.spec_capable?` ask the *installed* okf what it
can do, rather than inferring it from a version number. That is
[okf-capability-drift](/decisions/okf-capability-drift.md), and it is why this
gem carries [no version ceilings](/decisions/no-version-ceilings.md): a probe
degrades a feature, a ceiling refuses to install.

The one place the coupling is sharper than a probe can cover is the search
facade — [search-facade-coupling](/decisions/search-facade-coupling.md) is the
edge, and it is a private-surface dependency pinned by name in the suite.
