---
type: Capability
title: The fourteen tools
description: Every tool this server defines — what it answers, what it is kin to on the CLI, and the builder that constructs it — as one table, so nothing gets rebuilt for want of knowing it exists.
tags: [mcp, tools, catalog, search, retrieval]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/server.rb
---

# The catalog

Fourteen, and the number is a decision rather than a resting point: tool-list
weight is a real cost on every host, so adding one is a design decision. Check
this table first — `dirs` + `index` + `search` compose to most retrieval, and
the commonest mistake is building a fifteenth tool for something three of these
already answer together.

Every one is a **read-only lens**: `readOnlyHint` and a `title` on all fourteen,
`additionalProperties: false` on every input schema, and a declared output shape
looked up by name (`read_concept` alone has none — it answers markdown).

| tool | answers | builder |
| ---- | ------- | ------- |
| `list_bundles` | what exists: every bundle this server knows — slug, title, root, concept count | `list_bundles_tool` |
| `dirs` | the first move: a bundle's shape, one row per directory | `dirs_tool` |
| `index` | the §8 index map, one directory at a time: authored `index.md` bodies, rollups, listings | `index_tool` |
| `search` | find concepts: every term must match (AND) across title, id, tags, type and body | `search_tool` |
| `read_concept` | one concept's full markdown, frontmatter and body, live from disk | `read_concept_tool` |
| `catalog` | per-concept metadata for a whole bundle, projectable down to the fields asked for | `catalog_tool` |
| `tags` | the tag index: every tag with its count and concepts, ordered by count | `tags_tool` |
| `types` | the type index: every type with its count and concepts, ordered by count | `types_tool` |
| `stats` | bundle rollups in one answer: concepts, dirs, types, cross-links, distinct tags | `stats_tool` |
| `log` | the append-only history: every `log.md`, root scope first | `log_tool` |
| `validate` | the spec §11 conformance verdict, with every error | `validate_tool` |
| `lint` | the curation report: reachability, backlog, completeness, freshness, provenance | `lint_tool` |
| `graph` | the knowledge graph in three bounded views — never with concept bodies | `graph_tool` |
| `references` | the `references/` tree (§6.3): every file, its citers, and every pointer that resolves to nothing | `references_tool` |

Each builder lives in [the server definition](../structure/server-definition.md)
and calls the kernel. None of them analyses anything itself.

# Kin to a CLI verb, and that is the point

Every row above has a counterpart in `okf <verb>`, and the answers are the same
because both call the same kernel method. That is the
[kernel-first rule](../design/kernel-first.md) doing its job: a host and a
terminal cannot disagree about whether a bundle is conformant.

So the way to add a capability is usually **not** to add a tool here. It is to
add it to the kernel, where the CLI, the graph server, the TUI and this shell
all reach it.

# What every list answer carries

`total` appears on every list answer and means one thing everywhere: **how many
rows the request matched, before any `limit` cut them**. There is no silent
truncation anywhere in this gem, and a new tool that returns rows owes the same
field with the same meaning.

Domain failures become tool errors carrying the kernel's own sentences — never
a bare `-32603` — and both channels always: the JSON text an older client reads
and the same object as `structuredContent`.

`test/unit/bundle_catalog_test.rb` fails if this table and the tools
`server.rb` defines ever disagree, in either direction.

# The doctrine is elsewhere

*Why* each tool exists, what was rejected, and the reasoning behind the
bounded-output rules is `capabilities/mcp-server.md` in the repository's root
bundle. This table is the catalog; that concept is the argument. Neither
restates the other.
