---
type: Component
title: okf-tui — the terminal UI
description: Six views over one bundle or many, in a full-screen terminal — and the only surface that edits the registry, which it does without ever writing a bundle.
resource: gems/okf-tui
tags: [gem, tui, terminal, registry]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: gems/okf-tui
    resource: https://github.com/serradura/okf/tree/main/gems/okf-tui
  - title: gems/okf-tui/README.md
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/README.md
---

# What it is

`okf-tui` on RubyGems, at `gems/okf-tui/`. Six views — bundles, browse, search,
graph, health, help — over the active bundle, plus a search that spans every
bundle in scope. Read one while searching all of them.

# What holds it in shape

| | |
|---|---|
| Ruby floor | **2.4** — okf's |
| Runtime dependencies | `okf` plus one TTY gem per job; a seventh is a design decision, not a convenience |
| Entry point | no executable — `okf tui` through the kernel's plugin seam |
| The one rule | **it invents no analysis**: every number on screen is one okf computed |

# The line it holds

It edits the **registry** freely — register, remove, re-default, rename, group —
and never writes a **bundle**: there is no `Bundle::Writer` anywhere in its
`lib/`. Authoring belongs to the kernel's CLI and to the skill. That line, not
read-versus-write, is what a proposed feature is judged against.

The corollary is the one that keeps biting: when the kernel renames a derived
field, this gem breaks *silently* — a wrong number that looks right. So a
derived value read here wants an agreement test that asks okf the same question
and compares, rather than a formula copied into a comment.

# Where its knowledge lives

`@okf-tui` — `gems/okf-tui/.okf/`, which ships inside the gem. Its `structure/`
area names every file under `lib/` and its `capabilities/` catalogues the six
views; both are pinned by a test.
