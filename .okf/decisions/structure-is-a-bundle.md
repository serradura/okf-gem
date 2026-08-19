---
type: Decision
title: A gem's structure is a bundle, not a section of its guide
description: Every gem's map of `lib/**` moved out of its maintainer guide and into its own bundle, where a test fails when the map and the tree disagree.
tags: [documentation, testing, bundles, governance]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: gems/okf/test/unit/bundle_catalog_test.rb
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/test/unit/bundle_catalog_test.rb
---

# The decision

Each gem carries a `.okf/` beside its code, and its `structure/` area names
every file under `lib/`, grouped by the layer that owns it. Its `AGENTS.md`
keeps the contract, the commands and the obligations a reviewer checks, and
routes there for the rest.

Three of the four also carry a `capabilities/` catalogue — the fourteen MCP
tools, okf-pro's sixteen verbs and nine checks, okf-tui's six views — because
that is the list an agent reads *before* building the fifteenth thing.

# Why a bundle rather than a heading

A hand-written map of `lib/**` in a guide is documentation that **rots
silently**. A file arrives, moves or leaves; the map keeps reading plausibly;
nobody finds out. It is accurate when written and indistinguishable from
accurate forever after.

Moving it only relocates that problem — unless something fails when the two
disagree. So each gem's `test/unit/bundle_catalog_test.rb` fails on:

* a file under `lib/` that **no** concept names;
* a file that **more than one** concept names, so ownership is single;
* a concept naming a file that is **gone**;
* a catalogue out of step with the constant it mirrors — `OKF::CLI.builtins`,
  `App::TABS`, `CLI::USAGE`, `CLI::HOOK_NAMES`, the tools `server.rb` defines.

# The kernel is the exception, and why

`gems/okf/.okf/` carries the file map and the walk a new verb owes, and nothing
else, because *this* bundle was okf's for most of its life. A second copy of a
catalogue is worse than none. What the same test does instead is pin the one
catalogue that already existed here, in place.

# The cost

Four bundles to maintain rather than four sections, and a reader who wants both
the rule and its argument now opens two files. That is the price of the rule in
[where knowledge lives](../design/where-knowledge-lives.md): the same fact in
one place, not two.
