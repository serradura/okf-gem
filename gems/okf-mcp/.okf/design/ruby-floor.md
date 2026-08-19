---
type: Constraint
title: The floor is 2.7, and it is inherited
description: The `mcp` SDK's floor, taken rather than chosen — so okf's 2.4 API list does not bind here, and nothing past 2.7 may appear in lib/ or test/.
tags: [ruby, floor, constraint]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: okf-mcp.gemspec
---

# 2.7, from the SDK

The floor is the `mcp` gem's, inherited rather than argued. That makes it
different in kind from okf's 2.4, which is a *position* — the tool should run
on the Ruby an OS already ships. Nothing here can run below what the SDK
supports, so there is no version of this gem that reaches okf's floor.

# What it admits, and what it still forbids

A sibling's floor is its own: **the root `AGENTS.md`'s 2.4 API list does not
bind here.** `filter_map`, `tally`, `Dir.glob(base:)`, `transform_keys`,
`Struct.new(keyword_init:)` and numbered block params are all available and
used.

What is forbidden is anything *past* 2.7, in `lib/` **and** in `test/`:
endless method definitions, hash-literal shorthand (`{x:}`), `Data.define`,
`it` as a block parameter, and the rest of 3.x. RuboCop's `TargetRubyVersion`
catches syntax; it does not catch APIs, so a 3.x method that parses fine on 2.7
is the failure mode to watch.

The suite is the check that matters — CI runs 2.7 through the current stable,
one job for this gem, and a 3.x-only spelling fails on the oldest column. That
is the same rule the [dependency floors](runtime-dependencies.md) are held to:
the floor tracks what the suite proves.

# The trap the floor sets in the HTTP bridge

`ThreadError` on a mutex in trap context is a 2.7 behaviour, and it is why the
signal trap in [the HTTP bridge](../structure/http-bridge.md) hands teardown to
a thread instead of doing it inline. That is a floor constraint expressed as
code, and it is the one place the floor is load-bearing rather than merely
declared.
