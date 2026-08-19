---
type: Overview
title: The OKF ecosystem at a glance
description: One format, one kernel, three shells over it, and three distribution surfaces — held together by the rule that no surface recomputes an answer the kernel already gives.
tags: [ecosystem, overview, architecture, governance]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: README.md
    resource: https://github.com/serradura/okf-gem/blob/main/README.md
  - title: AGENTS.md
    resource: https://github.com/serradura/okf-gem/blob/main/AGENTS.md
---

# The idea

Knowledge that humans and agents both read should live in **one** place, in a
format both can work with. [OKF](format/okf-format.md) is that format —
directories of Markdown with YAML frontmatter — and this repository is the
tooling that makes a directory of Markdown behave like a system: readable,
checkable, searchable, and governable.

Nothing here defines a new store. It gives leverage over knowledge that already
lives as text.

# The shape

**One kernel, three shells.** [okf](gems/okf.md) owns the format, the model and
every judgement about a bundle. [okf-mcp](gems/okf-mcp.md),
[okf-tui](gems/okf-tui.md) and [okf-pro](gems/okf-pro.md) are surfaces over the
answers it computes.

The rule that keeps them coherent is that **no shell recomputes a kernel
answer**. It is not a style preference: this repository has shipped a release
where a renamed kernel field left a surface reporting a wrong number that looked
entirely right, in two places, with a green suite either side of it.

They compose through two registries rather than a list of known parts, so
adding a fourth shell requires no edit to the kernel at all — see
[extension points](design/extension-points.md).

# The three ways it leaves this repository

| surface | who receives it |
|---|---|
| four gems on RubyGems | someone running `gem install` |
| [the plugin](plugin/) | someone adding this repository as a Claude Code marketplace |
| [the skills](skills/) | someone whose agent reads `skills/` in a git repository |
| [the resources](resources/) | someone copying a CI workflow into a project of their own |

Only the first is a package. The other three are files this repository publishes
by containing them, which is why they are governed here rather than in a gem.

# How it governs itself

The repository is its own first user. It carries five OKF bundles — this one and
one per gem — and `rake okf` validates and lints all five on every change, from
a registry it commits rather than from a list.

Two rules do most of the work. [The same fact lives in one
place](design/where-knowledge-lives.md), so a README, a maintainer guide and a
bundle answer three different questions and never the same one twice. And
[a rule nothing runs is not a rule](design/nothing-runs-it.md) — every
convention here either has something executing it or says out loud that it does
not.
