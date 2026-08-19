---
type: Component
title: The Skill and Its Installer
description: The companion agent skill ships from exactly one tree in this gem, and two generated copies elsewhere in the repository are regenerated rather than edited.
tags: [structure, skill, generated, single-source]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/skill.rb
---

# The file

| file | what it owns |
|---|---|
| `lib/okf/skill.rb` | `Skill.install` — the installer, its `ASSETS` tree, and `Skill::Error` |

`ASSETS` points at `lib/okf/skill/`, and **that tree is the single canonical
copy of the skill.** `okf skill <dest>` installs from it, so edit it there and
nowhere else.

`NAME` is `okf`, `SKILLS_DIR` is `skills`, and `nest:` decides whether the
install lands in a `skills/okf/` subdirectory or directly in the destination —
`--here` is the flag that turns it off. `force:` overwrites.

# Two generated copies exist, and neither is editable

`plugin/skills/okf` and `skills/okf` at the repository root are *generated*
copies — the Claude Code plugin's, and the one a generic skill installer reads.
`rake skill:sync` writes both from this tree and stamps the plugin manifest's
version.

Two guards fail on drift, both by file list **and** SHA-256 checksum:
`rake skill:verify`, which `build` depends on, and `test/plugin/sync_test.rb`.
So a release with a stale copy is impossible rather than a CI failure after the
fact.

# The markers in the skill text

Guidance lines in the skill carry stable anchors — `<!-- check:<lint-check-id> -->`
where a deterministic check enforces the point, `<!-- rule:okf-<slug> -->` for
pure-judgment craft. They render invisibly and sync verbatim into every copy, so
keep them on the line they annotate when you edit it. They exist so an eval can
pin a claim and a concept can cite one.

# Loading

The other shell that loads on demand is [the-cli](/structure/the-cli.md).

`skill.rb` is one of the two argv-facing shells that **do not** load with
`require "okf"` — the CLI is the other. `exe/okf` requires them, and so must any
test that drives them. An embedding application never pays for either.
