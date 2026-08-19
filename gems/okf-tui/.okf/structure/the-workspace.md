---
type: Component
title: The Workspace and the Model
description: Two files answering two different questions — which bundles this session can see, and everything there is to know about one of them — with the memoization that makes a repaint free.
tags: [structure, registry, model, memoization]
timestamp: 2026-08-19
---

# The files

| file | pure? | what it owns |
|---|---|---|
| `lib/okf/tui/workspace.rb` | shell | the bundles a session can see; the **only** registry writes in the gem |
| `lib/okf/tui/model.rb` | pure | one bundle, and every answer about it, memoized |

# Workspace: which bundles, and which of them count

`Workspace` holds `Entry` (a bundle: slug, dir, default?, registered?, loaded?)
and `Group` (a registry group, with `cyclic?` for the one it cannot resolve).
Its two axes are independent and it is worth stating plainly, because conflating
them is the mistake the code is shaped to prevent:

* **active** — `switch`, `active`, `model`: the one bundle the single-bundle
  views are about;
* **scope** — `scope`, `scoped?`, `toggle_scope`, `scope_all`, `scope_none`,
  `scope_only`, `scope_group`: the set search runs across.

[cross-bundle-scope](/interaction/cross-bundle-scope.md) is why they are two
things and not one.

`add`, `remove` and the rest of the mutators are the **only** writes to the
registry anywhere in this gem, deliberately — the boundary and what it refuses
are [registry-write-boundary](/decisions/registry-write-boundary.md).
`registry_backed?` and `registry_path` are how a view says which registry it is
looking at without guessing.

`search` is the cross-bundle one, and it goes through okf's search facade rather
than reimplementing ranking — with the sharp edge recorded in
[search-facade-coupling](/decisions/search-facade-coupling.md).

# Model: every answer about one bundle, computed once

`Model` is pure and **memoized**, and both properties are load-bearing. Pure,
because the app repaints the entire frame on every keystroke
([whole-frame-painting](/rendering/whole-frame-painting.md)) and a view that
recomputed a lint on each one would be unusable. Memoized, for the same reason.

What it already answers — read this before computing anything in a view:

| question | reader |
|---|---|
| the bundle's concepts, as rows | `rows`, `row_by_id`, `concept_by_id` |
| the catalog and the graph | `catalog`, `graph` |
| conformance and curation | `validation`, `lint`, `skipped_checks` |
| the two v0.2 postures | `trust_posture`, `status_posture`, `shows_trust?` |
| size and shape | `concept_count`, `edge_count`, `orphan_ids`, `hubs` |
| the directory tree | `dirs`, `dir_traffic`, `dir_arcs`, `under_dir?` |
| the facets | `types`, `tags`, `types_of`, `tags_of`, `statuses_of`, `tiers_of` |
| what the bundle declares itself to be | `okf_version` |

Every one of those is okf's judgement, not this gem's. `Model` is a reader over
the kernel's analysers, and the rule that keeps it that way is
[invents-no-analysis](/decisions/invents-no-analysis.md): a number on screen
that okf did not compute is a number that will disagree with `okf lint`.

`UNTYPED` and `type_label` are the one exception, and they are labelling rather
than analysis — a concept with no `type` still needs a row.
