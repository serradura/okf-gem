---
type: Component
title: The Claude Code plugin
description: One thin command that routes to the skill's playbooks, a generated copy of the skill, and a manifest whose version must track the gem's — enforced at build time rather than by memory.
resource: plugin
tags: [plugin, claude-code, skill, generated]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: plugin/
    resource: https://github.com/serradura/okf/tree/main/plugin
  - title: plugin/commands/gem.md
    resource: https://github.com/serradura/okf/blob/main/plugin/commands/gem.md
---

# What is in it

| path | what it is |
|---|---|
| `plugin/commands/gem.md` | one thin command that routes to a playbook in the skill, or to the skill itself |
| `plugin/skills/okf/` | a **generated** copy of the skill — 27 files, never edited here |
| `plugin/hooks/hooks.json` | the registration for [the curation hook](curation-hook.md) |
| `plugin/.claude-plugin/plugin.json` | the manifest, carrying the version |

# The generated copy is the part that goes wrong

The skill has exactly one canonical tree, inside the gem
(`gems/okf/lib/okf/skill/`). This copy and the one under [`skills/`](../skills/)
are written from it by `rake skill:sync`, which also stamps the version into
`plugin.json`.

Two guards fail on drift, both by file list **and** SHA-256 checksum:
`rake skill:verify`, which `build` depends on, and `test/plugin/sync_test.rb`.
A release with a stale copy is therefore impossible, rather than a CI failure
noticed afterwards.

The task lives in the *gem's* Rakefile even though it writes files above it, and
that is deliberate: every input is the gem's — the skill tree and the version —
and keeping it there is what lets `task build: "skill:verify"` stay a plain
dependency.

# The version is not decoration

The plugin versions **with the gem**, so every bump has to reach
`plugin.json`. Nothing about a manifest makes that automatic; the sync task and
its two guards are what turn forgetting it into a stopped release.
