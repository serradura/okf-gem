---
type: Component
title: The okf skill
description: The companion agent skill that teaches an agent to author and curate bundles — one canonical tree inside the gem, and two generated copies that a stranger may install from.
resource: skills/okf
tags: [skill, agent, generated, distribution]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: skills/okf
    resource: https://github.com/serradura/okf/tree/main/skills/okf
  - title: gems/okf/lib/okf/skill
    resource: https://github.com/serradura/okf/tree/main/gems/okf/lib/okf/skill
---

# One tree, three places

The canonical copy is **inside the gem**, at `gems/okf/lib/okf/skill/`. That is
what `okf skill <dest>` installs from, and it is the only place to edit.

Two generated copies exist, written by `rake skill:sync`:

| copy | who reads it |
|---|---|
| `skills/okf/` | a generic skill installer — `npx skills add` walks `skills/` in any git repository |
| `plugin/skills/okf/` | [the Claude Code plugin](../plugin/claude-code-plugin.md) |

One canonical tree with two destinations is **one obligation, not two**: a
second task to remember is a second task to forget, so the single `skill:sync`
writes both.

# Why the copies are guarded rather than trusted

`skills/` is the one a stranger installs from without ever seeing this
repository, so a drifted copy there is a skill shipped to somebody at a version
nobody edited. `rake skill:verify` compares file lists and SHA-256 checksums for
every destination and `build` depends on it; `test/plugin/sync_test.rb` asserts
the same in CI.

# The markers in the text

Guidance lines carry stable anchors — `<!-- check:<lint-check-id> -->` where a
deterministic check enforces the point, `<!-- rule:okf-<slug> -->` for
pure-judgment craft. They render invisibly and sync verbatim into every copy, so
an eval can pin a claim and a concept can cite one. Keep a marker on the line it
annotates when editing that line.
