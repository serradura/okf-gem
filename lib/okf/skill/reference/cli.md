# OKF tool verbs — the `okf` CLI

`validate`, `lint`, `loose`, `search`, `index`, `catalog`, `files`, `tags`, `types`,
`stats`, `server`, `render`, and `graph` are **not** eyeball passes and are not
reimplemented in this skill. They run the deterministic `okf` executable shipped by
the companion gem — the single source of truth for OKF mechanics. Your job is to
invoke it correctly and interpret the result, not to reason out conformance by hand.

## When it isn't installed

Don't probe for the tool before using it — just run the verb. A shell `okf:
command not found` is the only thing that means the gem isn't installed: say so
and stop (`gem install okf`, or from a checkout `cd gem && bundle exec rake
install`); never fabricate a result. Any line that starts `error:` is the CLI
*answering* — a bundle or usage result to read, not a missing toolchain.

## Invocation

The surface is self-describing — `okf --help` maps every verb, `okf <verb> --help`
its flags. Ask the tool for what exists; this file carries only what `--help`
cannot: each verb's semantics, its traps, and its JSON shape.

**`--json` is compact by design.** Every emitting verb prints single-line JSON —
the token-efficient substrate you consume; `--pretty` (which implies `--json`)
indents it for a human. The bytes differ, the JSON is identical, so parse either.
When you only need to *scan* a bundle, the plain text views are lighter still than
JSON (they print each key once, not per row) — reach for `--json` when you need to
extract structure, not merely read it.

**Project the JSON to what you'll read.** On `index`, `catalog`, and `files`,
`--fields a,b` keeps only those properties and `--except a,b` drops them
(mutually exclusive; both imply `--json`; an unknown name is a usage error that
lists the valid ones). Projection happens before emission, so you pay no tokens
for a field you dropped — e.g. `okf index <dir> --except body,listing` is the lean
directory *skeleton* (structure + rollups), and on a large bundle that is the
difference between a few hundred bytes and hundreds of KB, since the per-item rows
(`listing`) dominate at scale. `okf index --no-body` is shorthand for dropping just
`body`.

**Every output names its bundle.** Two keys, one meaning each: `bundle` is
always a directory, `slug` always a registry slug. Name a bundle by `@slug` and
the answer comes back in that identity — `OKF lint — @handbook (/path/to/one)`,
and `{ "bundle": "/path/to/one", "slug": "handbook", … }` — so an agent holding
several bundles never has to remember which invocation produced which output.
A bundle named by path carries no `slug`: it may not have one, and inventing a
name it was never given would imply a registration that does not exist.

**@slug — point any verb at a registered bundle.** Wherever a `<dir>` goes,
`@slug` names a bundle registered via `okf registry set`, and bare `@` the
registry's default. They resolve through `$OKF_HOME` (default `~/.okf`) — the
single lever on which registry *any* verb reads, and it names exactly one, with
no fallback behind it. The slug is normalized as registration
normalized it — `@One` finds the bundle from dir `One` — but never to a
placeholder: `@***` names nothing, not a bundle. An unknown slug, a
registered-but-gone directory, or a malformed registry file is a usage error
(exit 2) whose message names the registry file consulted and the next move —
an explicit ask fails hard, never silently skipped. So `okf lint @handbook`
or `okf index @` work from any directory, no path recall needed.

**Exit codes:** `0` success · `1` non-conformant bundle (or a `lint --fail-on`
threshold crossed) · `2` usage error. `graph`, `server`, and `render` are best-effort
(§9): a file the reader cannot use — frontmatter that will not parse, or a file it
cannot open at all — is skipped and noted on stderr, never fatal. The note counts;
`validate` names each file and why.

**One bundle per verb, except two.** Only `search` merges several bundles and only
`server` mounts them; hand a second bundle to any other verb — two dirs, two refs,
or a mix — and it is a usage error (exit 2), never a silent answer about the first.
To ask the same question of several bundles, ask `search`, or ask each in turn.

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
`loose` surfaces the set so you can judge intent (see the
[maintain playbook](../playbooks/maintain.md)).

## search — ranked text retrieval (metadata + body)

The browser page's search brought to the CLI and extended to bodies, so "which
concept covers X?" costs rows, not body reads. `okf search <dir> <term…>`:
terms AND together — every term must hit at least one searched field, not
necessarily the same one — matched **literally against raw text** by default, or
as Ruby regular expressions with `--regexp`/`-e` (an invalid pattern is a usage
error, exit 2). `--fuzzy` forgives typos; pairing it with `-e` is a usage error,
since a pattern is matched literally rather than by edit distance.
`--in a,b` restricts the searched fields (title, id, tags, type, description,
body); the shared `--type/--area/--tag` filters narrow the candidates *first*,
so a search scoped by what `index` taught you stays surgical.

**The default is exact, so an exact query means what it looks like.** A phrase in
one argument (`"dedup key"`), a dotted version (`7.2.0`), an underscored
identifier (`customer_id`), a mid-word fragment (`ustomer`) and a word written in
`backticks` all match literally. This is what the scan engine buys, and it is the
default precisely because those queries are the common ones and the alternative
loses them silently. <!-- rule:okf-search-exact-identifiers -->

**`--engine index` is the other engine, and the one to reach for when ranking
matters more than exactness.** The engine is normally chosen by what the query
needs — `--fuzzy` routes to the index, anything else stays on the default scan —
and nothing is printed about the choice. `--engine NAME` overrides that for the
case the flags cannot express: a matching *model* requires no capability, so no
flag selects one. Under the index, terms match whole tokens and their prefixes
(`dedup` finds `deduplication`), rows rank by BM25+, and it is the engine the
browser page runs — so name it when reconciling a CLI answer with the page. The
cost is real: its tokenizer splits on punctuation, so identifiers shatter
(`customer_id` → `customer` + `id`), an infix finds nothing, and a backtick is
never split off at all, so a word inside a code span is unfindable — a large
silent loss, since technical prose is full of them. **Do not count on ranking to
rescue it** — BM25 normalizes by field length, so a short concept dense in `7`,
`2` and `0` can outrank the one that actually says `7.2.0`. Naming an engine that
cannot do what you also asked (`--engine index -e`) is a usage error naming one
that can. <!-- rule:okf-search-engine-choice -->

**The capabilities, and which engine has them.** An engine is selected by what
the query *requires*; only a matching model has to be named, because requiring
nothing is not something a flag can express:

| Flag | Capability | Engine | What it does |
|---|---|---|---|
| *(none)* | — | scan | literal substring over raw text; scores by summed field weight |
| `-e` / `--regexp` | `regexp` | scan | each term is a Ruby regexp, case-insensitive; invalid → exit 2 |
| `--fuzzy` | `fuzzy` | **index** | edit distance 0.2 × term length — and switches engine |
| `--engine index` | — | index | whole-token + prefix matching, BM25+ ranking, browser parity |
| `--engine scan` | — | scan | the default, spelled out |

Two consequences worth holding. **`--fuzzy` is an engine switch, not a mode**: it
carries the whole index with it, so a run that wanted one typo forgiven also gets
shattered identifiers and unfindable code spans — fix the spelling and stay on
the default when you can. And **`-e` moves nothing** now, because the default
engine already offers `regexp`; it changes how a term is *read* (pattern rather
than literal), not where it is matched. <!-- rule:okf-search-fuzzy-is-a-switch -->

`prefix` is a capability the index declares but no flag selects — it is always on
there. **It is not a reason to reach for the index**: a substring match already
covers every prefix and then some, so `dedup` finds `deduplication` under both
engines, while `duplication` and `uplicat` find it under the default only. Prefix
is what the index needs to catch up to raw text, not a capability it adds on top.
The index's real advantages over the default are exactly three — relevance
ranking, typo tolerance, and page parity.

**Search spans bundles.** Leading @refs pick several registered bundles
(`okf search @handbook @notes auth`); **`@all`** is the ref that means every one.
Rows from different bundles are ranked together and comparable, and each row
carries its bundle's slug. Under `--engine index` the bundles go into **one
corpus** — BM25 prices a term by how rare it is, so separately-ranked lists would
not compare — which makes a score relative to the whole answer: the same concept
scores lower searched beside others than searched alone. The default scan needs
no such trick — its score is absolute, so a row is worth the same either way.
This is the
cross-bundle retrieval the in-page search does not have: one question, every
bundle you keep. <!-- rule:okf-search-all -->

`@all` is a ref, not a flag, which is what keeps the grammar single: slot 1 is
always a bundle identity, so a directory there is a directory and nothing can
flip it into a term. Being a ref, it is normalized like one — `@ALL` and `@All`
name every bundle just as `@One` names the bundle registered from dir `One`. It composes accordingly — `@all @docs` expands and dedupes
(all ⊇ docs), needing no diagnostic. **Asking for everything tolerates gaps;
naming one bundle demands it**: `@all` skips a bundle whose directory has
vanished with a note on stderr, while `@docs` fails hard. `@all` is only
`search`'s: every other verb answers about one bundle, so it refuses `@all` by
name rather than letting the answer depend on how many bundles you happen to
have registered. `all` is reserved as a slug — a directory named `all/` registers
as `all-2`, `--as all` is refused, and an `all` row already in the registry file
(hand-typed, or written before the name was reserved) is read as `all-2` rather
than taken as grounds to reject the file — so `@all` is never ambiguous, and the
reservation never strands a registry it inherited. **The read normalizes every
slug** the same way registration would, so a hand-typed `"slug": "My Docs"` lists
and resolves as `my-docs`; an entry the listing shows is always an entry `@slug`,
`rename`, and `default` can name.

`--fields` projects the shape the mode actually emits: `slug` is available in
registry mode, and a usage error naming the real fields on a path-named search,
which has no slug to give. Two sharp edges: every *leading* @-arg is taken as a ref, so a literal @-term
(`@babel/core`, a Ruby `@ivar`) needs a non-@ term before it or `-e '\@term'` —
the CLI notes both traps on stderr — and any ref, even one, switches the JSON
envelope (next paragraph).

Rows rank by where they hit — title 5, id 4, tags 3, type/description 2, body 1 —
summed as an absolute score by the default scan, and carried as per-field boost
into **BM25+** under `--engine index`. Each row carries one bounded context
snippet from the strongest match that needs context (description or body). Every row still names the fields that hit (`matched`), so a result stays
citable rather than being a bare relevance number. Exact by default: the
consuming agent is the fuzzy layer — when terms miss, learn the bundle's
vocabulary from `tags`/`types` and re-ask in its own words, rather than
hammering synonyms or reaching for `--fuzzy` before you have looked. Advisory read: **exit 0 even with zero matches**.
JSON, plain-dir mode: `{ bundle, query, count, matches: [{ id, title, type,
area, tags, matched, score, snippet }] }`. Registry mode — any leading @ref,
`@all` among them — swaps the envelope: `{ bundles: [{ slug, dir }, …],
query, count, matches: [{ slug, id, … }] }`; a parser must branch on which form
it called. The head maps each slug to its dir once, so a row resolves to
`<dir>/<id>.md` without a second lookup and without repeating a path per row.
Both are projectable with `--fields/--except`, and projection is literal — when
merging bundles, put `slug` in your `--fields` list or the row label drops and
same-id concepts from different bundles become indistinguishable. The retrieval procedure that puts this verb in sequence —
map first, finder second, bodies last — is the
[search playbook](../playbooks/search.md).

## index — the progressive-disclosure map (§6)

The "orient before you read" view, and the read verb that sees the layer the
concept views can't: `index.md` files are reserved/structural, so
`catalog`/`files`/… never show them (in the browser, the Indexes tab and
folder clicks render this same map). `okf index <dir>` prints one entry per directory
that holds concepts or carries an `index.md`, root first — the authored index body
(frontmatter stripped), a `type`/`tag` rollup over the concepts that live directly
there, its child directories, and the concept listing. Run it first when picking up
an existing bundle: it is the cheapest high-signal orientation, and it surfaces
enumeration drift a grep can't (you can't grep for a listing entry that is *missing*).

`--area A` narrows to a directory and is **repeatable** — `--area model --area
format` shows both; `root` names the bundle root. `--no-body` drops the prose to a
skeleton (headers, rollups, child pointers). For a directory that has concepts but
**no `index.md`**, the listing is **synthesized** from the concepts' descriptions
and tagged `(no index.md)` — §6 explicitly permits synthesizing a map on the fly.

It is a **read view**: advisory, always exit 0. A synthesized directory is a
*signal* (a map worth writing), never a defect — `index` emits no lint findings and
never fails a bundle. JSON: `{ bundle, count, directories: [{ dir, index_path,
present, synthesized, count, types, tags, subdirs, body, listing: [{ id, title,
description, type, tags }] }] }`.

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
  count, concepts: [id, …] }] }`. `--by type|area` regroups the list per concept
  dimension with **within-group** counts (a tag spanning groups appears in each) —
  the substrate for tag curation; the judgment recipe lives in the
  [maintain playbook](../playbooks/maintain.md). JSON: `{ bundle, count, by,
  groups: [{ <dim>, count, tags: […] }] }`.
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
initial load stays small and edits show without a restart. Mermaid code blocks
in a body render as diagrams, and a click (or tap) opens the diagram full
screen with drag-to-pan and wheel/pinch zoom. Concepts render as nodes
coloured by `type` and sized by degree, links as edges, with a detail panel
(rendered markdown, "Links to" / "Linked from" backlinks), layout switching,
type/area/tag filters on every view, and search. The authored layer is in the
UI too: the Files view carries **Files | Indexes** tabs — the Indexes tab
lists the log first (the chronological index), then every `index.md` — and
folder nodes in file-tree mode and area boxes in cluster mode open a
directory's §6 map in the inspector (authored, or synthesized when none
exists). Links to an `index.md`, `log.md`, or bare directory navigate instead
of dead-ending, and the log is fetched fresh on every read, so a
just-appended entry shows without a restart. `?view=index` jumps straight to
the Indexes tab. It is a Rack app, so the same server can be mounted in a
host app (e.g. Rails).

**Hosting many bundles (the hub).** `okf server` takes zero or more dirs.
One dir is the classic single bundle at `/`. Two or more mounts each under
`/b/<slug>/` behind a hub, `/` redirects to the default, and `/b/` is a
self-contained **bundle index** (every hosted bundle, concept counts, default
marked — the browser counterpart of `okf registry`). An unknown slug 404s as a
page listing the hosted bundles, so a stale bookmark after a rename gets a way
home. With **no** dir it serves the *persistent registry*, a plain JSON file
under `$OKF_HOME` (default `~/.okf`), managed by the
`okf registry` umbrella — like git's `remote` family, and split by what each
verb keys on. **Entry verbs** take a path: `okf registry set <dir>` adds it
(slug from the basename, or `--as`, which errors on a collision; `--default`
puts it first), and because the entry is keyed by path, `set` on an
already-registered dir updates it in place — refreshing its title, and renaming
it when `--as` is given. `okf registry del <dir|@slug>` removes one — by name, so an entry whose
directory is already gone still deletes. Slug *or* dir, never both readings at
once: an argument with a `/` in it names a location and only a location, so
`del ./notes` refuses when no entry points there rather than stripping to the
slug `notes` and deleting a bundle somewhere else entirely.
<!-- rule:okf-registry-del-path-or-slug -->
**Slug verbs** take the name — bare, or as an `@slug`: `okf registry default <@slug>`
chooses which bundle `/` opens **by moving that entry to the front**, and
`okf registry rename <@slug> <new>` renames a slug (mount path and switcher
name) — `<new>` is a name being minted, so it is never a ref. The registry is ordered and **the first entry still on disk is the
default** — that is the whole rule, so the first bundle you register is the
default until you move another one, a rename keeps its position, and a `del`
promotes whatever is next. A vanished directory is stepped over (the server
cannot open one, so starring it would name a bundle `/` never serves), and
`registry default @slug` refuses one outright — the same refusal `registry set`
gives a directory that is not there. The file is hand-editable and reorders
visibly, which is the point: there is no stored slug that can dangle.
<!-- rule:okf-registry-default-position -->
`okf registry list` (or a bare
`okf registry`) stars the default and flags vanished dirs `(missing)` — the
server skips those with a note; `--json` answers
`{ registry: <file>, count, bundles: [{ slug, title, dir, mount, default,
missing }] }`, naming the file it read so a `$OKF_HOME` mismatch is visible. The hub roster is a
**boot-time snapshot**: restart `okf server` after registry changes. Behind a
hub the page gains a **bundle switcher** (⌘/Ctrl-K, or the rail button with its
bundle-count badge): the current bundle is pinned, the default chipped; ⏎
opens, ⌘/Ctrl-⏎ opens a new tab, and the current view carries over. Switching
is a server-only affordance — a static `render` file has no siblings and shows
none.

**Bundle-less run.** Register bundles once, then `okf server` (no dir) hosts
them all with the registry's first entry still on disk at `/` — the way to keep
several bundles a keystroke apart without re-passing paths.
`okf server @a @b` serves a registry subset, each mounted under its registered
slug — but as with any dirs-given run, the *first argument* lands at `/`; the
registry's own order applies only to the bundle-less run.

**Trust boundary:** the page renders each fetched markdown body through
DOMPurify and escapes everything it inlines (every `<` in the graph data is
escaped, so it cannot break out of its `<script>`), but it still loads its
viewer libraries (Cytoscape, marked, DOMPurify — plus Mermaid and Panzoom,
lazy-loaded on first use) from a CDN and renders whatever
links the bundle carries — so only serve bundles you trust.

## render — static graph export

Writes the same interactive page as one static, self-contained HTML file
(`okf render <dir>`), so the graph hosts where there is no server — GitHub Pages,
an object store, an attachment. Prints to stdout (`okf render <dir> > graph.html`)
or writes `-o FILE`; `--title`/`--link`/`--layout` mirror `server`. It is the same
template `server` renders, one switch apart: rather than fetching each body,
description, catalog, index, and log live, `render` bakes the whole bundle into
the page and the browser reads from that embedded payload — no server, no build
step. The trade-off is weight (every body is inlined), so `server` stays the
choice for a bundle too large to ship whole.

**Trust boundary:** the same two guards as `server` — every inlined body is
`</script>`-escaped like the graph data and still sanitized by DOMPurify when
rendered — so a static file is no laxer than the live server. Only render bundles
you trust.

## graph — the raw structure

Prints the node/edge graph. `--json` emits a machine-readable dump — the
`bundle`/`slug` head every view carries, then `nodes` (with
`id`/`type`/`title`/`description`/`tags` **and, by default, every `body`** — the
part that dominates the bytes on a real bundle) plus `edges` — you can pipe into
other analysis. A concept with a missing *or blank* `type` indexes under
`Untyped`: §9.2 rejects both identically, so both land in one bucket. To *plan* a traversal, structure is all you need: `--no-body`
drops each node's body, and `--minimal` ships only `id`/`title` plus the type/tag
indexes — the lean shape the `server` page boots from. Reach for the full dump
only when the task truly consumes every body; for one question, the
[search verb](#search--ranked-text-retrieval-metadata--body) is orders cheaper.
