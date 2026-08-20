---
type: Component
title: The Model
description: A bundle and its concepts in memory, with no disk and no stdio anywhere in it — plus the four derived views every other layer reads instead of recomputing.
tags: [structure, model, pure, graph]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/bundle.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/concept.rb` | one concept: frontmatter, body, and every §5 question about it |
| `lib/okf/bundle.rb` | the set: concepts, reserved files, and the rollups |
| `lib/okf/bundle/graph.rb` | nodes and edges, plus the type and tag indexes |
| `lib/okf/bundle/references.rb` | the `references/` inventory and who cites what |
| `lib/okf/bundle/row_filter.rb` | one predicate for `--type/--dir/--tag/--status/--trust` |
| `lib/okf/bundle/skeleton.rb` | directories, the arcs between them, and the suggested cut |

All six are **pure**. No `File`, no `Dir`, no stdio — `test/unit/boundary_test.rb`
fails the build if that changes.

# Concept: the §5 vocabulary lives here

`Concept` is where the spec's provenance model is implemented, and the parts
worth knowing before adding a field:

* `RESERVED_FILENAMES` and `reserved?` — `index.md` and `log.md` are not concepts.
* `STATUSES` / `DEFAULT_STATUS` / `effective_status` — §4.1's lifecycle, with the
  default applied once so no caller has to remember it.
* `generated`, `generated_at`, `generated_by`, `declared_generated?` — a
  *declared* provenance, never a derived one.
* `verified`, `fold_tier`, `shows_trust?` — the trust tiers, and the predicate
  that decides whether a bundle even has a trust dimension to show. That last one
  is a single predicate on purpose: a UI that gates a chip one way and a facet
  another promises rows it will not return.
* `ISO_DATE`, `ISO_CUTOFF`, `ATTESTED_COMPUTATION`, `HUMAN_ACTOR` — the literals
  the validator and the linter both read, rather than each spelling them.

`CONCEPT_SCOPED_CHECKS` is the list of lint checks that are about one concept, and
it is here rather than in the linter because it is a fact about the model.

# Bundle: the rollups every other layer reads

`Bundle` holds `concepts`, `reserved` and `unparseable` — an unreadable file is
kept as an `Entry` with its error rather than dropped, because a validator that
silently skips what it could not parse reports a clean bundle.

`catalog`, `stats`, `hubs`, `directories`, `directory_index`, `tag_groups` and
`paths_by_id` are the derived views. Read one rather than recomputing it: the
CLI, the server, the TUI and the MCP shell all answer from these, which is what
keeps four surfaces from disagreeing about the same number.

`okf_version` is what the bundle *declares* (§12), never a literal — the health
of every downstream v0.1-versus-v0.2 decision depends on that distinction.
`VIRTUAL_ROOT` is the path a rootless in-memory bundle is contained against.

The two analysers that read all of this are [the-analysers](/structure/the-analysers.md).

# Graph, Skeleton, References, RowFilter

`Graph.build` turns concepts into nodes and their links into edges, with
`type_index` and `tag_index` alongside. `unlinked_ids` is the orphan set.
`minimal:` and `body:` are how a caller asks for less than the whole thing —
the payload the graph page embeds is not the payload `okf graph --json` prints.

`Skeleton` is the directory-level view: `dirs`, `arcs` between them, and
`suggested_cut` — the weight at which the arc diagram stops being a hairball.
`cuts_for` maps that back onto concrete edges.

`References` inventories the `references/` folder and the concepts citing each
file, including the dangling ones.

`RowFilter.matches?` is the *single* predicate behind every `--type`, `--dir`,
`--tag`, `--status` and `--trust` filter in the CLI, the server and the TUI.
`shows_trust?` is the same gate `Concept` exposes, reachable from a catalog row.
A second filter implementation is how two views come to disagree about what
"matching" means.
