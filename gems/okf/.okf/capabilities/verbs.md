---
type: Capability
title: The Verbs
description: Every `okf` command and subcommand, grouped as `okf help` groups them, with what each answers — and the flags every one of them inherits from the base class.
tags: [cli, verbs, capabilities]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/cli.rb
---

# The catalogue

The command registry is the source of truth for this table, and a test holds the
two together. The order is the order `okf help` prints, which is the require
order at the bottom of `cli.rb`.

| verb | answers |
|---|---|
| `skill` | install the companion agent skill |
| `server` | serve one bundle, or many behind a hub |
| `render` | write a static, self-contained HTML graph |
| `registry` | the `@slug` layer — eight subcommands, below |
| `lint` | report curation-quality issues |
| `loose` | list files with no graph links, by folder |
| `validate` | check OKF v0.2 conformance |
| `search` | find concepts by text or regexp, ranked — across bundles with several `@slug`s or `@all` |
| `index` | the index map: dirs, their listings and rollups |
| `dirs` | list the bundle's dirs and their concept counts |
| `stats` | bundle rollups — concepts, dirs, types, links, tags |
| `types` | list types with their concepts, by count |
| `tags` | list tags with their concepts, by count; `--by DIM` regroups per dimension |
| `files` | list files with titles, by folder |
| `references` | inventory `references/` files and the concepts citing them |
| `catalog` | list concepts with metadata, by top-level dir |
| `graph` | print the knowledge graph; `--traffic` prints directories and the link traffic between them |

## `registry`, and its eight subcommands

Each is a surface a user invokes on its own, and each earns its own test file.

| subcommand | answers |
|---|---|
| `init` | create a project-local `.okf-registry.json` (the nearest one wins) |
| `list` | list registered bundles (`*` marks the default) |
| `set` | add or update a bundle |
| `del` | remove a bundle or group |
| `default` | move a bundle to the front |
| `rename` | rename a bundle or group |
| `group` | create a group, or add members |
| `ungroup` | remove members from a group (emptying it deletes it) |

# What every verb inherits

Do not add these to a verb; they come from `CLI::Command`. How they are
implemented is [structure/the-cli](/structure/the-cli.md).

* **`@slug` addressing everywhere a `<dir>` goes** — a registered slug, bare `@`
  for the default, `@group` for a group. `@all` is `search`'s alone.
* **`--json`, and `--pretty` to indent it.**
* **`--fields` / `--except`** to project the JSON (`search`, `index`, `catalog`,
  `files`).
* **`--type`, `--dir`, `--tag`, `--status`, `--trust`** — each view takes the
  ones orthogonal to it, matching case-insensitively. `--dir` takes a directory
  and everything below it; `root` (or `.`) is the bundle root. It replaced
  `--area`, which still works and warns.
* **`--depth`** where a tree is printed.
* **the exit codes** — `0` ok, `1` a failing bundle, `2` a usage error. A verb
  that takes one bundle refuses a second with exit 2 rather than ignoring it.

# The three installed extensions

`mcp`, `pro` and `tui` are not in this gem. They arrive through
`CLI.register`, and `okf help` prints them under their own heading — which is
the seam working, and the reason there is no list of known addons anywhere in
`cli.rb`.
