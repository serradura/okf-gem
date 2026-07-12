---
type: Component
title: The okf command-line front end
description: The only layer that parses argv, prints, writes files, and decides exit codes.
resource: lib/okf/cli.rb
tags: [cli, shell]
timestamp: 2026-07-11T21:40:00Z
---

# Overview

`OKF::CLI` is the executable's front end and the single place where the gem
touches the outside world for a command: it parses `argv`, prints, writes files,
and chooses the exit code. Every library class beneath it just returns data — the
CLI is the [shell half](design/core-shell-split.md) of the architecture. Output
streams are injected (`out:`/`err:`) so the whole surface is driven in tests
without a real terminal or socket.

# Subcommands

Dispatch is a single `case` on the first argument. The verbs fall into three
groups:

| Group | Verbs | Notes |
|-------|-------|-------|
| Judge | `validate`, `lint`, `loose` | [validate](capabilities/validator.md) and [lint](capabilities/linter.md) answer different questions and stay separate. |
| Read | `catalog`, `files`, `types`, `tags`, `stats`, `graph` | the [browser views as text](capabilities/read-views.md). |
| Act | `server`, `skill` | boot the [graph server](capabilities/graph-server.md); install the [agent skill](capabilities/agent-skill.md). |

Plus `version` / `--version` / `-v` and `help` / `--help` / `-h`.

# Exit codes

The contract every verb keeps:

| Code | Meaning |
|------|---------|
| `0` | success — including a bundle with lint findings (`lint` is advisory) |
| `1` | a non-conformant bundle (`validate`) or a `lint --fail-on warn` threshold crossed |
| `2` | usage error — unknown command, missing directory, bad flag |

# Best-effort reads

`graph`, `server`, and the read views are best-effort under §9: a file with
invalid frontmatter is kept in `bundle.unparseable`, skipped, and *noted on
stderr* (so JSON on stdout stays clean) rather than aborting the whole command.
One bad file never breaks the rest. Run [validate](capabilities/validator.md) for
the details of what was skipped.

# Citations

[1] [lib/okf/cli.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli.rb) — the dispatch, option parsing, and printers.
