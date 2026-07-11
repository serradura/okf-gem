---
type: Constraint
title: Exactly two runtime dependencies
description: The gem depends on rack and webrick only — no ActiveSupport, no build step, no JavaScript toolchain.
resource: okf.gemspec
tags: [dependencies, rack, portability]
timestamp: 2026-07-11T12:00:00Z
---

# Overview

The runtime dependencies are exactly two, and adding a third is a design decision
to be challenged, not a convenience:

| Gem | Why |
|-----|-----|
| `rack` (`>= 2.2`) | the [server](../capabilities/graph-server.md) is a mountable Rack app |
| `webrick` (`>= 1.4`) | the default runner — unbundled from Ruby in 3.0, so it must be declared |

# No ActiveSupport, on purpose

The gem refuses the usual reach for ActiveSupport. Two small pieces exist
precisely so it is not needed:

- `OKF.blank?` — the emptiness check;
- `OKF::Markdown::Frontmatter.stringify_keys` — the key coercion, living in
  [the one YAML gateway](../format/frontmatter.md).

# What the leanness buys

Together with the [Ruby 2.4 floor](ruby-floor.md), a two-dependency footprint is
what lets the gem run on the interpreter an OS already ships — no build step, no
bundler for the [served page](server-trust-boundary.md), no JavaScript toolchain.
Leanness is a feature of this gem, not an accident.

# A packaging note

`spec.files` comes from `git ls-files` minus `test/`, `bin/`, `.github/`, etc., so
a new top-level file ships in the gem unless the gemspec rejects it — check
`gem build` output when adding one.

# Citations

[1] [okf.gemspec](https://github.com/serradura/okf-gem/blob/main/okf.gemspec) — the two `add_dependency` lines and `spec.files`.
