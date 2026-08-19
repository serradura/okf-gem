---
type: Component
title: The curation hook
description: A PostToolUse hook that nudges curation after an edit — plain Ruby on the stdlib, on the kernel's 2.4 floor, and the one file no gem's RuboCop reaches.
resource: plugin/hooks/scripts/curate.rb
tags: [plugin, hook, ruby, lint, ci]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: plugin/hooks/scripts/curate.rb
    resource: https://github.com/serradura/okf-gem/blob/main/plugin/hooks/scripts/curate.rb
---

# What it is

A PostToolUse hook, registered by `plugin/hooks/hooks.json`, that runs after an
edit inside a bundle. It is **plain Ruby on the stdlib** — no gem, not even okf —
because a hook that must resolve a bundle before it can run is a hook that is off
on the machine where it mattered. It holds the kernel's 2.4 floor for the same
reason.

# It is why a repository-level lint job exists

This file sits outside every gem, so **no gem's `rake rubocop` reaches it**. The
root `.rubocop.yml` inherits the kernel's and covers exactly this file and the
root Rakefile.

That inheritance was once described in a commit as "restoring lint coverage"
while, in CI, nothing ran it at all. Adding a single `lint` job on one modern
Ruby is what made the claim true. The general form of that failure is
[a rule nothing runs](../design/nothing-runs-it.md).
