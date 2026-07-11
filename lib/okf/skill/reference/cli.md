# OKF tool verbs — the `okf` CLI

`validate`, `lint`, `loose`, `catalog`, `files`, `tags`, `types`, `stats`, `server`,
and `graph` are **not** eyeball passes and are not
reimplemented in this skill. They run the deterministic `okf` executable shipped by
the companion gem — the single source of truth for OKF mechanics. Your job is to
invoke it correctly and interpret the result, not to reason out conformance by hand.

## Presence guard

Check the tool exists before relying on it. If it is missing, the gem is not
installed — say so and stop; never fabricate a result:

```bash
command -v okf >/dev/null || echo "okf CLI not found — install it: 'gem install okf' (or from a checkout: 'cd gem && bundle exec rake install')"
```

## Invocation

```bash
okf validate  <dir> [--json]
okf lint      <dir> [--json] [--fail-on warn] [--only a,b] [--except a,b] [--min-body N] [--stale-after DUR]
okf loose     <dir> [--json]
okf catalog   <dir> [--json] [--type T] [--area A] [--tag T]
okf files     <dir> [--json] [--type T] [--area A] [--tag T]
okf tags      <dir> [--json] [--type T] [--area A]
okf types     <dir> [--json] [--area A] [--tag T]
okf stats     <dir> [--json]
okf server    <dir> [-p PORT] [--bind ADDR] [--layout NAME] [-t title] [-l url]
okf graph     <dir> [--json] [--minimal] [--no-body]
```

**Exit codes:** `0` success · `1` non-conformant bundle (or a `lint --fail-on`
threshold crossed) · `2` usage error. `graph` and `server` are best-effort
(§9): a file with invalid frontmatter is skipped and noted on stderr, never fatal.

## validate — the hard gate (§9)

Implements the spec's §9 conformance definition exactly:

- **§9.1** every non-reserved file has a parseable YAML frontmatter block;
- **§9.2** every such block has a non-empty `type`;
- **§9.3** any `index.md`/`log.md` present follows §6/§7 (a nested `index.md` has
  no frontmatter, a root `index.md` carries only `okf_version`, `log.md` date
  headings are ISO `YYYY-MM-DD`).

`ERROR`s are the three conditions above; the bundle is non-conformant until every
one is fixed. `warn`s are soft — missing recommended fields, non-list tags, an
unparseable timestamp, and **broken cross-links, which §5.3 explicitly tolerates**.
Fix warnings when cheap; never block on them. Use `--json` in CI.

## lint — curation quality (advisory)

Asks the complementary question to `validate`: not "is this legal OKF?" but "is
this well-curated, navigable, trustworthy?" — precisely over the things §9 forbids
`validate` from rejecting. It has its own report, never emits conformance errors,
and **exits `0` even with findings** unless you pass `--fail-on warn`.

Six conceptual categories, each backed by individual checks (names in parens):

- **reachability** — orphans, concepts not in any index, disconnected islands,
  and unlinked (degree-0) files
  (`orphan`, `not_in_index`, `disconnected_component`, `unlinked`)
- **backlog** — demand-ranked missing concepts (linked-to but absent), broken index entries
  (`missing_concept`, `broken_index_entry`)
- **completeness** — stubs, missing `title` / `description` / `timestamp`
  (`stub`, `missing_title`, `missing_description`, `missing_timestamp`)
- **freshness** — concepts older than a cutoff (`stale`) — **only computed when you
  pass `--stale-after`; a plain `okf lint` never reports staleness at all**
- **provenance** — uncited external claims, broken citations, spec §8
  (`uncited_external`, `broken_citation`)
- **hygiene** — duplicate titles, unused/undefined reference links, self-links
  (`duplicate_title`, `unused_reference_def`, `undefined_reference`, `self_link`)

`--only` / `--except` filter by the **individual check names above**, not the
category labels — `okf lint <dir> --only orphan,stub` works; `--only reachability`
is an error. Two knobs tune specific checks: `--min-body N` sets the `stub` body
threshold in characters (default 50), and `--stale-after DUR` sets the `stale`
cutoff — a duration like `90d` or `12w`, or an ISO date like `2026-01-01` (a bare
number is rejected).

`lint --json` is the structured substrate you consume to reason about the two
things lint deliberately does **not** compute — contradictions and *semantic*
staleness — which need understanding of meaning.

## loose — files with no graph connections (by folder)

Lists the **loose** files — concepts with graph **degree 0**: no cross-links in
*or* out — grouped by folder. It is a focused, folder-organized view over `lint`'s
`unlinked` check (`okf loose <dir>` ≈ `okf lint <dir> --only unlinked`, regrouped),
for the "which files float in the graph?" question. Advisory: **exits `0`**; `--json`
emits `{ bundle, count, loose: [{ id, title, dir }] }`.

**Loose ≠ orphan** — the trap. `lint`'s `orphan` is about *reachability*, and an
`index.md` listing makes a file reachable, so an indexed file is never an orphan.
But an index listing is **not a graph edge**: a file can be listed in an index yet
have no cross-links, so it floats in the graph while `lint` reports it as reachable.
`loose`/`unlinked` catch exactly that gap. A loose file is not automatically a
defect — a terminal leaf (a backlog item, a spec reference) can be loose by design;
`loose` surfaces the set so you can judge intent (see `maintain` in authoring.md).

## catalog / files / tags / types / stats — the server views, as text

The browser server (below) has Catalog, Files, Tags and Stats panels; these
verbs reproduce them on the CLI so an agent can read a bundle without a browser.
All are advisory reads (exit 0) sharing one data source (per-concept metadata plus
in/out link degree). Add `--json` to any for a machine substrate.

- **`catalog`** — every concept with its metadata (type, status, tags, timestamp,
  in/out link degree, description), grouped by top-level area. The "what's here, in
  detail" view. JSON: `{ bundle, count, concepts: [{ id, title, type, description,
  tags, timestamp, status, backlog_ref, dir, area, links_out, links_in }] }`.
- **`files`** — the folder tree: each concept's filename + title, grouped by
  directory. The "how it's organised" view. JSON: `{ bundle, count, files: [{ path,
  id, dir, type, title, description }] }`.
- **`tags`** — every tag with the concepts that carry it, ordered by count
  descending. The "what themes dominate" view. JSON: `{ bundle, count, tags: [{ tag,
  count, concepts: [id, …] }] }`.
- **`types`** — every type with the concepts that carry it, ordered by count
  descending. The "what kinds of knowledge" view. JSON: `{ bundle, count, types:
  [{ type, count, concepts: [id, …] }] }`.
- **`stats`** — bundle rollups: concept / area / type / cross-link / distinct-tag
  totals plus per-type and per-area breakdowns. The "shape at a glance" view. JSON:
  `{ bundle, concepts, areas, concept_types, cross_links, distinct_tags, by_type, by_area }`.

The four list views narrow with the same filters the browser panels offer —
`--type TYPE`, `--area AREA`, `--tag TAG`; each takes the ones orthogonal to
itself (`tags` can't filter by tag). Matching is case-insensitive and exact; a
concept at the bundle root lives in the `(root)` area, which `--area` also accepts
as plain `root` (no shell quoting). A filter that matches nothing is an empty view,
not an error: `okf tags <dir> --area billing --json` answers "which tags does the
billing area use?", `okf catalog <dir> --tag auth` answers "what carries the auth
tag?".

Reach for `stats` first to size a bundle, `catalog`/`files` to enumerate it, `tags`
to find thematic clusters — all without standing up the server.

## server — interactive graph server

Starts a local HTTP server (`okf server <dir>`; `-p`/`--port`, default 8808, and
`--bind`) and prints its URL — stop it with Ctrl-C. The page boots from a lean
payload (nodes carry only `id` and `title`, plus compact type/tag indexes) and
fetches each concept's markdown body **live from disk** as you click it, so the
initial load stays small and edits show without a restart. Concepts render as nodes
coloured by `type` and sized by degree, links as edges, with a detail panel
(rendered markdown, "Links to" / "Linked from" backlinks), layout switching,
type/area/tag filters on every view, and search. It is a Rack app, so the same
server can be mounted in a host app (e.g. Rails).

**Trust boundary:** the page loads Cytoscape and marked from a CDN and
renders each concept's markdown body **without sanitization**, so only serve
bundles you trust. Inlined graph data cannot break out of its `<script>` (every
`<` is escaped), but the fetched markdown is rendered unsanitized.

## graph — the raw structure

Prints the node/edge graph. `--json` emits a machine-readable dump (`nodes` with
`id`/`type`/`title`/`description`/`tags`, and `edges`) you can pipe into other
analysis or use to plan a traversal before consuming a large bundle. `--no-body`
drops each node's body; `--minimal` ships only `id`/`title` plus the type/tag
indexes — the lean shape the `server` page boots from.
