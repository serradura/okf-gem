# `graph` — the raw structure

Kind: reference. Answers: what a full dump costs and how to plan a traversal
without paying it, plus the two rankings that give `refine` its evidence —
`--hubs` by concept, `--traffic` by directory.

The shared contract — `@slug` refs, exit codes, `--json` — is in
[cli.md](../cli.md) and is not repeated here.

Prints the node/edge graph. `--json` emits a machine-readable dump — the
`bundle`/`slug` head every view carries, then `nodes` (with
`id`/`type`/`title`/`description`/`tags` **and, by default, every `body`** — the
part that dominates the bytes on a real bundle) plus `edges` — you can pipe into
other analysis. A concept with a missing *or blank* `type` indexes under
`Untyped`: §11 condition 2 rejects both identically, so both land in one bucket. To *plan* a traversal, structure is all you need: `--no-body`
drops each node's body, and `--minimal` ships only `id`/`title` plus the type/tag
indexes — the lean shape the `server` page boots from. Reach for the full dump
only when the task truly consumes every body; for one question, the
[search verb](search.md) is orders cheaper.

`--hubs` swaps the dump for the **inbound ranking**: every concept with at
least one inbound link, ranked by inbound degree, each with its links grouped
by *source top-level dir* (`core/status  ×3   flows 2, billing 1`) — the evidence for
[refine](../../playbooks/refine.md)'s hub origin test ("is this hub well-homed?").
A source at the bundle root counts under `(root)`. JSON: `{ bundle, count,
hubs: [{ id, top_dir, inbound, by_top_dir: { <top_dir>: n } }] }`. Advisory read, exit 0;
`--minimal`/`--no-body` shape node payloads and change nothing here.

`--traffic` asks the same question one grain coarser: **directories**, not
concepts. Every concept collapses into the directory it lives in and every link
between two directories collapses into one weighted arc, so a bundle's wiring
becomes a table you can read — measured on one 47-concept bundle, 227 links
collapsed into 50 arcs, of which the fitted cut draws 22. Each row carries the
directory's traffic split three ways
(`internal` / `out` / `in`) plus **cohesion**, its internal share of the total:
the evidence for [refine](../../playbooks/refine.md)'s container test, where
`--hubs` only ever answered about concepts. Rows lead with the lowest cohesion,
so the directories with a case to answer come first, and a directory with no
traffic at all prints `—` rather than a `0%` it did not earn.

`--cut N` is the least arc weight drawn. It defaults to a value **fitted to the
bundle** — enough arcs for roughly 1.5 per directory, floored at 8 — because a
fixed weight cannot serve both ends: measured at weight 3 across ten bundles it
left 2 arcs on one and 136 on another. The JSON says which you got. Cohesion is
computed over *every* arc and never the drawn ones, so tightening the cut
changes the picture and never the evidence. JSON: `{ bundle, cut, fitted, dirs:
[{ dir, parent, count, subtree, internal, out, in, cohesion }], arcs: [{ source,
target, weight }], total_arcs }` — a fraction of the full dump (2.6 KB against
27 KB on that bundle), and the shape rather than the contents. Advisory, exit 0.
