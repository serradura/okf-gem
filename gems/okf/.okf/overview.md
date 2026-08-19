---
type: Overview
title: okf at a Glance
description: One kernel, a pure core with a thin shell around it, four ways in — and a deliberate refusal to grow a fifth dependency or leave the Ruby an OS already ships.
tags: [overview, architecture, kernel]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf.rb
---

# What it is

`okf` reads, validates, lints and serves Open Knowledge Format bundles:
directories of Markdown with YAML frontmatter that humans and agents both read.
It is the **kernel** of this ecosystem — the MCP shell, the TUI and the
enforcement layer are all readers of the answers this gem computes, which is why
none of them recompute one.

# One rule underneath the layout

**The core is pure and the shell does the I/O**, and it is enforced rather than
intended: `test/unit/boundary_test.rb` fails if a pure file names a shell class
or touches `File`, `Dir`, `FileUtils` or stdio.

That is what makes the model testable without a fixture, the analysers reusable
from four surfaces, and the writer able to validate a whole tree before
publishing it. [Structure](structure/) is the layer-by-layer map.

# Four ways in

| door | what it is for |
|---|---|
| `exe/okf` | the CLI — seventeen verbs, the only layer that parses argv and exits |
| `require "okf"` | the library — the model and the analysers, without the argv machinery |
| `okf server` / `okf render` | one ERB template, served or baked into a self-contained file |
| `okf skill` | the companion agent skill, installed into a project |

Plus a fifth that belongs to other gems: `CLI.register`, through which `okf mcp`,
`okf pro` and `okf tui` arrive with no edit here.

# What it deliberately is not

* **Not a framework.** Runtime dependencies are exactly `rack`, `webrick` and
  `minifts`. No ActiveSupport — `OKF.blank?` and
  `Markdown::Frontmatter.stringify_keys` exist precisely so it is not needed. A
  fourth gem needs an argument as strong as the third's.
* **Not on a modern Ruby.** The floor is **2.4**, rack's own, and the point is
  running on the Ruby an OS already ships. RuboCop parses at 2.4 but does not
  catch *APIs*, so the forbidden list in `AGENTS.md` is the real guard, and the
  Docker floor run is the proof.
* **Not an authoring tool.** Nothing in the CLI writes a bundle. `Bundle::Writer`
  exists for an embedding application; authoring is the skill's job and the
  user's.
* **Not a judge of curation at validate time.** `validate` answers conformance
  and `lint` answers quality, and the two may not borrow each other's findings —
  see [the-analysers](structure/the-analysers.md).
