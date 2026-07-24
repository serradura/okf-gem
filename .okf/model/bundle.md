---
type: Component
title: OKF::Bundle
description: The pure in-memory collection of concepts that validate, lint, and graph run over.
resource: okf/lib/okf/bundle.rb
tags: [pure]
timestamp: 2026-07-17T16:00:00Z
---

# Overview

`OKF::Bundle` is a set of [concepts](concept.md) held together in memory, with no
disk involved. It is the object the three judging capabilities operate on:
`#validate`, `#lint`, and `#graph` each hand the bundle to a dedicated pure
class and return a result. A bundle also carries the reserved files
(`index.md`, `log.md`) and — importantly — an `unparseable` list.

# Best-effort by construction

When a bundle is built from disk, files the reader cannot use do not vanish and do
not abort the build: they are collected in `bundle.unparseable` — frontmatter that
would not parse, and files that would not open, since a locked file is one file's
problem and not the bundle's. That is what
lets [graph](graph.md), the [server](../capabilities/graph-server.md), and the
[read views](../capabilities/read-views.md) render everything that *is* valid
while the [CLI](../cli.md) notes the skips on stderr — §9's best-effort posture,
made structural.

# Build it from data, not only from files

Because the bundle is pure, an embedding application can construct concepts
straight from its own records — no Markdown round-trip — and still get validate,
lint, and graph for free. This is the surface the
[library API](../capabilities/library-api.md) exposes to, say, a Rails store that
already holds knowledge as rows. It also feeds the shared `#catalog`, the data
behind every read view.

# Citations

[1] [okf/lib/okf/bundle.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/bundle.rb) — the in-memory collection and its `#validate` / `#lint` / `#graph` entry points.
