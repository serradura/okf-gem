---
type: Capability
title: Read views (index, dirs, catalog, files, types, tags, stats, loose, graph)
description: The server's browser panels reproduced on the CLI, plus the index map, so an agent reads a bundle at a glance without a browser.
tags: [read, cli, json]
timestamp: 2026-07-24T12:00:00Z
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
| `catalog` | concepts with type, tags, link counts, status | top-level dir |
| `files` | files with titles | folder |
| `types` | [types](../format/frontmatter.md) with their concepts | count |
| `tags` | [tags](../format/frontmatter.md) with their concepts | count |
| `stats` | rollups: concepts, dirs, types, cross-links, tags | — |
| `loose` | degree-0 concepts (no [links](../format/cross-links.md) in or out) | folder |
| `graph` | the raw nodes and edges; `--hubs` ranks inbound links by source top-level dir; `--traffic` collapses concepts into dirs and links into weighted arcs, with cohesion | — (`--minimal` / `--no-body`) |

`dirs` and `stats` answer about the *same* set of directories, deliberately:
both read `Bundle#directory_index`, the map `--dir` is resolved against. Grouping
the catalog instead — which knows only the directories that happen to hold a
concept — made the two verbs disagree about how big a bundle was (`stats` said 2
where `dirs` listed 3 on a bundle whose root carries an index.md and no
concepts), and worse, left a directory out of `by_dir` that `--dir` answers
about. Counts stay direct, so a directory holding nothing itself reports the zero
it holds rather than disappearing; `by_dir.keys` is therefore the complete list
of what `--dir` can name.

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
narrows to a directory and its subtree and repeats (`root` names the bundle
root) — bringing the chain up to the root with it, marked `↑`, since orientation
is the whole point of this view and a branch shown alone has lost it —
`--depth N` bounds how far below the starting point that reaches, and
`--no-body` drops the prose to a skeleton. The last two are what make the map
usable at scale: every directory is a section, so a few hundred concepts is a map
nobody reads whole — `--depth 1 --no-body` orients, `--dir <branch> --depth 1`
descends, and the pair walks the tree a level at a time instead of paging it. It is the cheapest orientation when picking up a
bundle, and the only view that exposes *enumeration drift* — a listing entry that
should exist but is missing, which no grep can find. A directory that holds
concepts but no `index.md` gets its listing synthesized and tagged `(no index.md)`,
a prompt to write a real map rather than a defect.

# `dirs` is the shape, `index` is the contents

`dirs` answers the question `--dir` is pointed at: every directory the bundle
has — those holding concepts, those carrying an `index.md`, and the empty
intermediates that exist only to connect the tree — with two counts each.

`count` is **direct**, never cumulative: the column sums to the bundle's concept
count, and a directory holding nothing but sub-directories reads `0` rather than
borrowing its children's weight. That honesty is also its limit, and why
`subtree` sits beside it: truncate the listing on a deep bundle and every row at
the top of the tree reads `0`, which is precisely where "where is the mass?" is
being asked. `subtree` is defined as *exactly what `--dir` on that row returns*,
so the number and the flag can never disagree — and the root's subtree is
therefore its own direct count, since `.` is a prefix of nothing. The human
table shows the second column only where some directory actually nests; a flat
bundle would only see the first one repeated.

`--dir` (repeatable) takes a subtree — **and the chain up to the root with it**,
so a branch is never shown adrift of the authored context that says what it is.
Those rows are marked (`↑`, `ancestor: true`) and stay out of `total`, which is
what keeps a row's `subtree` equal to the total `--dir` on that row returns;
`--no-ancestors` drops them. A `--dir` naming nothing gains no chain, since a
lone root row would read as a partial answer to a query that matched nothing.
`--depth N` bounds how far below the starting point the descent reaches — the `--dir` when one is given, the bundle root
otherwise. **Relative, not absolute**, so `--dir a/b --depth 1` reads "a/b and
one level under it" without the caller first working out how deep `a/b` is, and
the two compose the way a reader descending a tree actually moves. `--depth 0`
is the starting point alone. The deprecated `--area` combines with **neither**
`--depth` nor `--dir` and is refused (exit 2) for one reason wearing two shapes:
it is *exact*. With `--depth` it names no starting point to be relative to, so
the pair unioned the area with every directory at that depth from the root; with
`--dir` one side is exact where the other is a prefix, so the map came back with
the area *and* the subtree. Both read like an answer and are an answer to neither
question.

Matching folds case, but a row is found by its *stored* spelling, so the chain is
walked folded and handed back in the map's own words. It used to be handed back
folded, which silently dropped every ancestor of a directory spelled with a
capital — the chain the flag exists to draw, missing exactly the row that places
the branch.

One line per directory where `index` is the whole map, so it is the cheaper of
the two when the question is shape rather than contents — and `dirs` is the first
thing to run on an unfamiliar bundle. Cheaper structurally, not by measurement:
`dirs` emits one row per *directory* and `index` one listing row per *concept*
even under `--no-body`, so their costs scale with different things. The root stores `.` and
prints `(root)` — the split every grouped view keeps, so a table and its `--json`
never disagree about which spelling is the data.

# JSON output — compact, and projectable

`--json` is **compact by default** — single-line, the token-efficient substrate an
agent consumes; `--pretty` (which implies `--json`) indents the same JSON for a
human. On the per-item list views — `index`, `catalog`, `files`, `dirs` — `--fields a,b`
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
`root`) means the root alone. A trailing slash is accepted and ignored, because
the human views print one — `index` labels a row `platform/services/` — and a
flag that refuses the label the tool just printed answers "nothing found" to a
directory that is full. It replaces `--area`, which saw only a concept id's
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
hub's links by *source top-level dir* — whether a hub is well-homed, answered
mechanically.

`graph --traffic` asks it one grain coarser, about **directories**. It reads the
[skeleton](../model/skeleton.md): concepts collapse into the directory they live in
and the links between two directories into one weighted arc, so each row carries
that directory's traffic split three ways — internal, out, in — plus
**cohesion**, its internal share. That is
cohesion-versus-coupling applied to a knowledge tree, and it is the only read at
the grain `refine` actually decides at: `--hubs` says whether a *concept* is
well-homed, `--traffic` says whether a *directory* is holding together, acting
as a shared vocabulary everyone cites, or behaving like a projection that should
have been an index. `--cut` is fitted to the bundle rather than fixed, because a
fixed weight left 2 arcs on one bundle and 136 on another; cohesion is computed
over every arc regardless of the cut, so narrowing the picture never moves the
evidence.

# `loose` is a curation lens, not an error

`loose` is the folder-grouped view over [lint](linter.md)'s `unlinked` check —
distinct from `orphan`. An `index.md` listing makes a file *reachable* (not an
orphan) but is **not a graph edge**, so a listed file can still float here. A
loose file may be perfectly fine — a terminal leaf like a backlog item is loose
by design — so `loose` surfaces the set for a human or agent to judge and always
exits `0`.

# Citations

[1] [cli.md — read views](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/skill/reference/cli.md) — the views and their flags.
