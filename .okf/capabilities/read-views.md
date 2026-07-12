---
type: Capability
title: Read views (index, catalog, files, types, tags, stats, loose, graph)
description: The server's browser panels reproduced on the CLI, plus the index map, so an agent reads a bundle at a glance without a browser.
tags: [read, cli, json]
timestamp: 2026-07-12T12:00:00Z
---

# Overview

The [graph server](graph-server.md) renders a bundle in a browser; these verbs
render the same knowledge as text, so an agent (or a terminal) reads it directly.
Each prints a scannable human view by default and machine JSON with `--json`, and
all are advisory reads that exit `0`. They share
[`OKF::Bundle#catalog`](../model/bundle.md) and the
[graph indexes](../model/graph.md) for their data.

# The views

| Verb | Shows | Grouped by |
|------|-------|------------|
| `index` | each directory's index body, type/tag rollup, child dirs, and concept listing | directory (root first) |
| `catalog` | concepts with type, tags, link counts, status | area |
| `files` | files with titles | folder |
| `types` | [types](../format/frontmatter.md) with their concepts | count |
| `tags` | [tags](../format/frontmatter.md) with their concepts | count |
| `stats` | rollups: concepts, areas, types, cross-links, tags | — |
| `loose` | degree-0 concepts (no [links](../format/cross-links.md) in or out) | folder |
| `graph` | the raw nodes and edges | — (`--minimal` / `--no-body`) |

# `index` is the orient-first map (§6)

Alone among the read views, `index` shows the reserved `index.md` layer: the
concept views skip those structural files, so only `index` renders the
[progressive-disclosure map](../format/okf-format.md) — one entry per directory
(root first) with its authored index body, a type/tag rollup over the concepts
living directly there, its child directories, and the concept listing. `--area`
narrows to one directory and repeats (`root` names the bundle root); `--no-body`
drops the prose to a skeleton. It is the cheapest orientation when picking up a
bundle, and the only view that exposes *enumeration drift* — a listing entry that
should exist but is missing, which no grep can find. A directory that holds
concepts but no `index.md` gets its listing synthesized and tagged `(no index.md)`,
a prompt to write a real map rather than a defect.

# JSON output — compact, and projectable

`--json` is **compact by default** — single-line, the token-efficient substrate an
agent consumes; `--pretty` (which implies `--json`) indents the same JSON for a
human. On the per-item list views — `index`, `catalog`, `files` — `--fields a,b`
keeps only those properties and `--except a,b` drops them (mutually exclusive; an
unknown name is a usage error that lists the valid ones). Projection runs before
emission, so an agent never pays tokens for a field it dropped: `okf index <dir>
--except body,listing` is the lean directory skeleton, the difference between a few
hundred bytes and hundreds of KB on a large bundle.

# Narrowing and regrouping

The four list views — `catalog`, `files`, `types`, `tags` — accept the filters
*orthogonal* to how they group, so you ask a narrow question instead of paging
the whole bundle (matching is case-insensitive):

| View | Filters it accepts |
|------|--------------------|
| `catalog`, `files` | `--type`, `--area`, `--tag` |
| `types` | `--area`, `--tag` (it already groups by type) |
| `tags` | `--type`, `--area` (it already groups by tag) |

`tags --by type|area` regroups the tag index under each concept dimension with
within-group counts — the view for curating a
[tag](../format/frontmatter.md) vocabulary: which tags cluster in which area,
which type leans on which tags.

# `loose` is a curation lens, not an error

`loose` is the folder-grouped view over [lint](linter.md)'s `unlinked` check —
distinct from `orphan`. An `index.md` listing makes a file *reachable* (not an
orphan) but is **not a graph edge**, so a listed file can still float here. A
loose file may be perfectly fine — a terminal leaf like a backlog item is loose
by design — so `loose` surfaces the set for a human or agent to judge and always
exits `0`.

# Citations

[1] [cli.md — read views](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/reference/cli.md) — the views and their flags.
