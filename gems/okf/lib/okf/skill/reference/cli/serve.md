# Serving the graph — `server` and `render`

Kind: reference. Answers: what the interactive page shows and what it fetches
live, how several bundles mount behind one hub, what the static export trades
away, and the trust boundary both modes share.

The shared contract — `@slug` refs, exit codes, `--json` — is in
[cli.md](../cli.md) and is not repeated here.

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
type/dir/tag filters on every view (the dir chips take a directory *and* its
subtree, the same rule `--dir` uses), and search. Cluster mode groups the
concepts into one box per directory, nested to a depth picked beside the layout
select — depth 1 is the flat view, and a flat bundle is offered no control. The authored layer is in the
UI too: the Files view carries **Files | Indexes** tabs — the Indexes tab
lists the log first (the chronological index), then every `index.md` — and
folder nodes in file-tree mode and directory boxes in cluster mode open a
directory's §8 map in the inspector (authored, or synthesized when none
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
home. With **no** dir it serves the *persistent registry*. The hub roster is a
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
registry's own order applies only to the bundle-less run. A `@group` argument
fans out to its member bundles in the same way (`okf server @backend`), its first
member landing at `/`; `okf search @group <term…>` merges the group's members
into one ranking, exactly as naming them individually would.
The registry itself — the file it reads, how okf finds it, and the verbs that
write it — is in [registry.md](registry.md).

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

