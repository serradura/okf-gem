---
type: Component
title: okf — the kernel
description: "The baseline gem every other one depends on: it defines the model, answers every question about a bundle, and owns the CLI, the graph server and the agent skill."
resource: gems/okf
tags: [gem, kernel, cli, library]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: gems/okf
    resource: https://github.com/serradura/okf-gem/tree/main/gems/okf
  - title: gems/okf/README.md
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/README.md
---

# What it is

`okf` on RubyGems, at `gems/okf/`. It reads, validates, lints, searches, serves
and renders [OKF v0.2](../format/okf-format.md) bundles, and installs the
companion agent skill. Four doors: the `okf` executable, `require "okf"`,
`okf server` / `okf render`, and `okf skill`.

It is the only gem here that ships an executable, and the only one the other
three depend on.

# What holds it in shape

| | |
|---|---|
| Ruby floor | **2.4** — rack's own; the point is running on the Ruby an OS already ships |
| Runtime dependencies | exactly `rack`, `webrick`, `minifts` — no ActiveSupport, by design |
| Enforced boundary | the core is pure, the shell does the I/O, and a test fails the build if a pure file touches the disk |

The arguments for all three, and everything about how the code is arranged, are
the gem's own bundle: `@okf`.

# The seam the other three arrive through

`OKF::CLI.register` lets any gem named `okf-*` with an `okf/plugin.rb` on the
load path add a verb, with no edit here and no list of known addons. That is why
`okf mcp`, `okf tui` and `okf pro` exist without this gem knowing they do —
see [extension points](../design/extension-points.md).

# Where its knowledge lives

`@okf` — `gems/okf/.okf/`, which ships inside the gem. Its `structure/`
area names every file under `lib/` and is pinned by a test, so a file that
arrives without a line in the concept that owns its layer is a red suite rather
than a stale document.
