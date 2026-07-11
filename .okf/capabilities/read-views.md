---
type: Capability
title: Read views (catalog, files, tags, stats, loose, graph)
description: The server's browser panels reproduced on the CLI so an agent reads a bundle at a glance without a browser.
tags: [read, cli, json]
timestamp: 2026-07-11T12:00:00Z
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
| `catalog` | concepts with type, tags, link counts, status | area |
| `files` | files with titles | folder |
| `tags` | [tags](../format/frontmatter.md) with their concepts | count |
| `stats` | rollups: concepts, areas, types, cross-links, tags | — |
| `loose` | degree-0 concepts (no [links](../format/cross-links.md) in or out) | folder |
| `graph` | the raw nodes and edges | — (`--minimal` / `--no-body`) |

# `loose` is a curation lens, not an error

`loose` is the folder-grouped view over [lint](linter.md)'s `unlinked` check —
distinct from `orphan`. An `index.md` listing makes a file *reachable* (not an
orphan) but is **not a graph edge**, so a listed file can still float here. A
loose file may be perfectly fine — a terminal leaf like a backlog item is loose
by design — so `loose` surfaces the set for a human or agent to judge and always
exits `0`.

# Citations

[1] [cli.md — read views](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/reference/cli.md) — the views and their flags.
