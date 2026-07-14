---
type: Component
title: OKF::Concept
description: The pure in-memory model of a single OKF file — frontmatter, body, and a stable id.
resource: lib/okf/concept.rb
tags: [pure]
timestamp: 2026-07-11T12:00:00Z
---

# Overview

`OKF::Concept` is the atomic node: a `path`, a parsed
[`frontmatter`](../format/frontmatter.md) hash, and a Markdown `body`. It is
[pure](../design/core-shell-split.md) — it holds no file handle and does no I/O.
The on-disk counterpart is `OKF::Concept::File`, part of the
[library API](../capabilities/library-api.md).

# The id is the concept's identity

`#id` is the `path` minus `.md` (e.g. `model/graph.md` → `model/graph`). That id
is the concept's **stable identifier** across the whole system — it is the graph
node key, the link target, and the thing you name a concept for. Name a file for
what it *is*, not where it sits, because the id follows the path.

# What it derives from its own content

The concept parses its body on demand into the structural facts the rest of the
gem consumes:

- `#type`, `#title`, `#description`, `#resource`, `#tags`, `#timestamp` — typed
  reads over the frontmatter;
- `#links` — the bundle-relative [cross-links](../format/cross-links.md) (edges);
- `#external_links` — URLs and `mailto:` (not edges);
- `#citations` — the [`# Citations`](../format/citations.md) entries;
- `#to_markdown` — the inverse of the frontmatter parser;
- `#lint` — the concept-scoped [lint](../capabilities/linter.md) checks in isolation.

A concept never decides conformance alone; a [bundle](bundle.md) does, because
some checks (duplicate titles, missing link targets) are only meaningful across
the set.

# Citations

[1] [lib/okf/concept.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/concept.rb) — the pure concept model.
