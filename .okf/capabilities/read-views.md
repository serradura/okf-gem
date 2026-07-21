---
type: Capability
title: Read views (index, dirs, catalog, files, types, tags, stats, loose, graph)
description: The server's browser panels reproduced on the CLI, plus the index map, so an agent reads a bundle at a glance without a browser.
tags: [read, cli, json]
timestamp: 2026-07-21T18:00:00Z
---

# Overview

The [graph server](graph-server.md) renders a bundle in a browser; these verbs
render the same knowledge as text, so an agent (or a terminal) reads it directly.
Each prints a scannable human view by default and machine JSON with `--json`, and
all are advisory reads that exit `0`. They share
[`OKF::Bundle#catalog`](../model/bundle.md) and the
[graph indexes](../model/graph.md) for their data. When the question is lexical —
"which concept covers X?" — [ranked search](search.md) cuts across every field
these views group by, for the price of a few rows.

# The views

| Verb | Shows | Grouped by |
|------|-------|------------|
| `index` | each directory's index body, type/tag rollup, child dirs, and concept listing | directory (root first) |
| `dirs` | every directory with the concepts living directly in it | directory (root first) |
| `catalog` | concepts with type, tags, link counts, status | area |
| `files` | files with titles | folder |
| `types` | [types](../format/frontmatter.md) with their concepts | count |
| `tags` | [tags](../format/frontmatter.md) with their concepts | count |
| `stats` | rollups: concepts, dirs, types, cross-links, tags | — |
| `loose` | degree-0 concepts (no [links](../format/cross-links.md) in or out) | folder |
| `graph` | the raw nodes and edges; `--hubs` ranks inbound links by source area | — (`--minimal` / `--no-body`) |

Every one of them names the bundle it answers about, in the identity the caller
used — the rule the [CLI](../cli.md) keeps: `bundle` is always the directory,
`slug` always a registry slug, and a header that reads `@handbook (/path)` when a
[ref](../registry.md) named it. `graph` was the last holdout, printing a bare pair
of counts over a bare `nodes`/`edges` payload; an agent holding several bundles
had nothing in that answer to tell them apart.

# `index` is the orient-first map (§6)

Alone among the read views, `index` shows the reserved `index.md` layer: the
concept views skip those structural files, so only `index` renders the
[progressive-disclosure map](../format/okf-format.md) — one entry per directory
(root first) with its authored index body, a type/tag rollup over the concepts
living directly there, its child directories, and the concept listing. `--dir`
narrows to a directory and its subtree, and repeats (`root` names the bundle
root); `--no-body`
drops the prose to a skeleton. It is the cheapest orientation when picking up a
bundle, and the only view that exposes *enumeration drift* — a listing entry that
should exist but is missing, which no grep can find. A directory that holds
concepts but no `index.md` gets its listing synthesized and tagged `(no index.md)`,
a prompt to write a real map rather than a defect.

# `dirs` is the shape, `index` is the contents

`dirs` answers the question `--dir` is pointed at: every directory the bundle
has — those holding concepts, those carrying an `index.md`, and the empty
intermediates that exist only to connect the tree — with the concepts living
**directly** in each. Direct, never cumulative: the column sums to the bundle's
concept count, and a directory holding nothing but sub-directories reads `0`
rather than borrowing its children's weight. One line per directory where
`index` is the whole map, so it is the cheaper of the two when the question is
where the mass sits. The root stores `.` and prints `(root)` — the split every
grouped view keeps, so a table and its `--json` never disagree about which
spelling is the data.

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
| `catalog`, `files` | `--type`, `--dir`, `--tag` |
| `types` | `--dir`, `--tag` (it already groups by type) |
| `tags` | `--type`, `--dir` (it already groups by tag) |

`--dir` is one rule: a concept matches when its directory *is* the path or sits
below it, so `--dir platform` reaches `platform/services/api` and `--dir .` (or
`root`) means the root alone. It replaces `--area`, which saw only a concept id's
first path segment — a word the [OKF format](../format/okf-format.md) never used —
and which still works, warning on stderr, until a later release drops it.

`tags --by type|dir` regroups the tag index under each concept dimension with
within-group counts — the view for curating a
[tag](../format/frontmatter.md) vocabulary: which tags cluster in which directory,
which type leans on which tags. Each row also carries the tag's total across
the narrowed set, printed `count/total` when they differ (`async  2/3`) and as
a plain count when the tag is wholly local — so a tag's *locality* (domain
confined to one directory, or concern cutting across several) reads per row. The
same evidence question for the graph: `graph --hubs` ranks every concept with
inbound [links](../format/cross-links.md) by inbound degree and groups each
hub's links by *source area* — whether a hub is well-homed, answered
mechanically.

# `loose` is a curation lens, not an error

`loose` is the folder-grouped view over [lint](linter.md)'s `unlinked` check —
distinct from `orphan`. An `index.md` listing makes a file *reachable* (not an
orphan) but is **not a graph edge**, so a listed file can still float here. A
loose file may be perfectly fine — a terminal leaf like a backlog item is loose
by design — so `loose` surfaces the set for a human or agent to judge and always
exits `0`.

# Citations

[1] [cli.md — read views](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/reference/cli.md) — the views and their flags.
