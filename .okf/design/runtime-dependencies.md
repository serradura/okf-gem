---
type: Constraint
title: Three runtime dependencies, each challenged
description: The gem depends on rack, webrick and minifts only — no ActiveSupport, no build step, no JavaScript toolchain, and no native extension.
resource: okf.gemspec
tags: [rack, portability]
timestamp: 2026-07-19T03:00:00Z
---

# Overview

The runtime dependencies are exactly three, and a fourth is a design decision to
be challenged, not a convenience:

| Gem | Why |
|-----|-----|
| `rack` (`>= 2.2`) | the [server](../capabilities/graph-server.md) is a mountable Rack app |
| `webrick` (`>= 1.4`) | the default runner — unbundled from Ruby in 3.0, so it must be declared |
| `minifts` (`~> 1.0`) | [search](../capabilities/search.md)'s index engine — BM25+ ranking, prefix and fuzzy matching, on request |

# What the third one had to prove

`minifts` was admitted because it costs the footprint nothing that the two
before it were chosen to protect. It is pure Ruby with **zero runtime
dependencies of its own**, so it adds one gem rather than a subtree; it holds the
same [Ruby 2.4 floor](ruby-floor.md); and it is not a native extension, which is
the whole point — it is what lets ranked full-text search arrive *without*
SQLite + FTS5 and the C toolchain, build step and platform matrix that come with
it. The ceiling moves up; it does not disappear. A corpus large enough to
outgrow an in-memory index is still FTS5's to answer.

It buys a second thing that no third-party gem usually can. `minifts` is a
bit-for-bit port of the JavaScript MiniSearch the [browser
page](../capabilities/graph-server.md) already loads, so `--engine index` and the
browser rank identically by construction rather than by two implementations
agreeing for a while — and an index built in Ruby can be searched in the browser,
which is what a cached, pre-built index would need.

**The case got weaker, and the entry stays honest about it.** `minifts` now backs
a **non-default** engine: the scan took the default back, because a one-shot CLI
cannot amortize an index build (3.00 s against 0.24 s at 1,000 concepts) and
because raw text has none of the tokenizer's recall holes. A dependency that only
serves an opt-in path is a dependency carrying less weight than the one admitted
here. It is not close to retirement — `--fuzzy` has no other implementation,
BM25+ ranking has no other source, and page parity has no other route — but the
argument that justified it was *ranked search by default*, and that is no longer
what it delivers. If a cached prebuilt index makes the index viable as the
default again, this entry is restored rather than merely re-argued.

# No ActiveSupport, on purpose

The gem refuses the usual reach for ActiveSupport. Two small pieces exist
precisely so it is not needed:

- `OKF.blank?` — the emptiness check;
- `OKF::Markdown::Frontmatter.stringify_keys` — the key coercion, living in
  [the one YAML gateway](../format/frontmatter.md).

# What the leanness buys

Together with the [Ruby 2.4 floor](ruby-floor.md), a three-dependency footprint —
none of them native, none of them dragging a tree — is what lets the gem run on
the interpreter an OS already ships: no build step, no bundler for the
[served page](server-trust-boundary.md), no JavaScript toolchain. Leanness is a
feature of this gem, not an accident.

# A packaging note

`spec.files` comes from `git ls-files` minus `test/`, `bin/`, `.github/`, etc., so
a new top-level file ships in the gem unless the gemspec rejects it — check
`gem build` output when adding one.

# Citations

[1] [okf.gemspec](https://github.com/serradura/okf-gem/blob/main/okf.gemspec) — the three `add_dependency` lines and `spec.files`.
[2] [minifts](https://github.com/serradura/minifts) — the port: pure Ruby, no runtime dependencies, Ruby >= 2.4.
