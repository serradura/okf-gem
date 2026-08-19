---
type: Constraint
title: Exactly two runtime dependencies
description: "`mcp` and `okf`, nothing else — rack and webrick arrive through okf and must never be named here — with both floors held to one rule: the floor tracks what the suite proves."
tags: [dependencies, gemspec, constraint]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: okf-mcp.gemspec
---

# The two

`mcp` (the official SDK) and `okf` (the kernel). That is the whole list, and
`test/unit/gemspec_test.rb` pins it.

**rack and webrick arrive via okf.** Naming either one here would be the
mistake that looks like diligence: this gem uses both — the Rack seam and the
WEBrick bridge — but it uses them *because okf already depends on them*, and a
second declaration is a second version constraint to keep in sync with a gem
that owns the answer.

A third runtime dependency is a design decision, held to the same bar the
kernel holds its own: argue it, do not add it for convenience — and
[kernel-first](kernel-first.md) is usually the reason one is not needed.

# The floor tracks what the suite proves

One rule covers both, and it is the reason the pins are not round numbers.

**`mcp` is pinned pessimistically (`~>`)**, and the suite fails the day the
lockfile resolves past it. The listen and modern-path tests exercise the
SEP-2575 wire, which 1.0 and 1.1 never served — against those versions the
tests fail, so the floor cannot admit them. The floor is not a guess about
compatibility; it is the oldest version the tests actually pass on.

**The `okf` floor may lead the kernel checkout but never lag it.** It names the
kernel version that ships what this shell rides — `Search.prepare/with/across`,
registry groups, project-local discovery, `dirs`, `Bundle#directories`, the
slug grammar. An earlier floor once admitted a kernel this code raises
`NoMethodError` against, because `Bundle#directories` did not exist there: the
gem installed cleanly and broke on the first `dir` refusal.

That is the failure the rule closes, and why the floor moves when the code
starts calling something new — in the same commit, not at the next release.
