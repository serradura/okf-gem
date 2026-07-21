---
type: Capability
title: Interactive graph server (server)
description: A self-contained HTML knowledge graph — served over HTTP as a mountable Rack app, one bundle or many behind a hub, or written to a single static file.
resource: lib/okf/server/app.rb
tags: [server, graph, rack, diagram]
timestamp: 2026-07-21T19:00:00Z
---

# Overview

`okf server` boots an interactive view of the [graph](../model/graph.md):
`OKF::Server::App` is a Rack app that serves one self-contained HTML page which
draws the bundle with Cytoscape and renders concept bodies with marked, sanitized
by DOMPurify. Because
it is a plain Rack app, it also mounts inside a host application (e.g. a Rails
route) — the built-in WEBrick runner is just the default, injected so tests drive
it without opening a socket.

# The page stays self-contained

One ERB template, inline CSS and JS, no build step and no bundler. The only
external assets are Cytoscape, marked, and DOMPurify from a CDN — plus Mermaid,
Panzoom, and MiniSearch, lazy-loaded on first use (a concept body's diagram
opened, the search box focused); everything else is inlined. A rendered Mermaid diagram
is **click-to-inspect**: a click, tap, or Enter re-renders it from source into a
fullscreen viewer — drag pans, wheel or pinch zooms, double-click resets, Esc
closes — so a wide flowchart is never stuck at panel width.
The graph draws from a **minimal** node payload and pulls each concept's body
**on demand** via `fetch()`, which is why even a large bundle loads fast. The
page also emits link-preview metadata — Open Graph and Twitter Card tags with a
social image, plus `theme-color` — so a shared `okf server` URL unfurls as a
proper card in chat and social apps.

# The same page, without a server

The same template also ships *without* a server: [`okf render`](render.md) bakes
the whole bundle into one static, self-contained HTML file, so the graph hosts
anywhere nothing can answer a `fetch()`. It is one switch apart from what `server`
serves — a single injected `EMBED` adapter swaps the live endpoints below for an
inlined payload — so there is no second renderer to keep in sync. See
[static render](render.md) for the embedded-data path, the baked-in flags, and the
weight it trades for needing no server.

# Many bundles behind one hub

`okf server` takes *zero or more* directories. One is the classic single bundle at
`/`; two or more mount ephemerally behind `OKF::Server::Hub`; none serves the
[registry](../registry.md), opening its chosen default. The hub is a Rack app in
front of one `App` per bundle, each at `/b/<slug>/`, with `/` redirecting to the
default.

Hosting under a prefix costs almost nothing, and that is a dividend of a decision
made earlier: the page's fetch endpoints were already **mount-relative**, so the
hub needs only a clean `PATH_INFO` strip and a trailing-slash redirect — no
rewriting, no per-mount configuration. The rough edges are all navigational: a
redirect preserves the query string (a deep link survives the hop), and an unknown
slug answers `404` with a *page listing the hosted bundles*, so a bookmark left
stale by a rename gets a way home instead of bare text. That page is a directory
reached by a wrong turn rather than an error page, and it is built that way: the
**asked path is the heading**, set in mono where a dropped slash reads as a
shape, with "not found" demoted to the eyebrow above it — a reader arrives
already knowing they are lost, so the diagnosis is the least useful thing on the
page. Where a slug nearly matches, the guess is a **row** carrying the same
anatomy as the list under it, already marked, with `⏎` pointed at it: a sentence
in muted grey asks a reader to read, parse and then aim. Moving through the list
is **Tab's** job — every row is an `<a href>`, a filtered-out row leaves the tab
order on its own, and `/` reaches the box from anywhere, the same key the graph
binds. A hand-rolled ↑↓ cursor was tried and deleted: it was a second focus model
beside the browser's own, invisible to a screen reader, and the two falling out
of step is what left two rows lit at once. And when the filter finds no bundle,
the page raises the **same bridge panel** the graph page's search box raises —
same component, same place, same two buttons — because it is the same event, and
a second dialect of one idea two pages apart is how a product stops feeling like
one. Rows carry the folder,
because a hub hosting `site/.okf`, `minifts/.okf` and `okf-core/.okf` has three
titles that read alike and the directory is all that tells them apart. Colour
marks only the exception — a healthy row draws no verdict edge at all, since a
rule on every row is a page where the one that matters cannot be found.

The guess reads the path, not only the slug the router parsed. `/bokf-tui/` is
`/b/okf-tui/` with one slash missing, which is the likeliest way a hand-typed URL
fails when every bundle lives at `/b/<name>/` — and the router, which only looks
*under* the mount, hands back no slug at all there. The dropped separator is
named outright only on evidence with no second reading (the remainder is a hosted
slug exactly, and the whole segment is not one); everything short of that gets a
sentence teaching the shape instead of guessing at the mistake. `/b/` itself is the
[bundles list](bundles-manager.md) — a hub is navigable without the
switcher, and the empty registry lands on a page that says so rather than
redirecting nowhere. Those pages are self-contained and theme-aware like the graph
page: no external requests.

The hub loads its bundles **at boot** and rebuilds them after any registry write
it serves, so a rename made on the manager page takes effect on the next click.
What it never does is re-scan disk per request: an edit made *elsewhere* while it
runs — `okf registry set` in another terminal — still wants a restart to be
served, though the manager page itself reads the file fresh and will show it.

# One search box for every bundle

The hub answers `GET /search?q=…`, which is the only route in the server that
knows about more than one bundle. It is
[`OKF::Bundle::Search.across`](search.md) over every hosted bundle at once —
one shared index, so BM25 weighs a term against the whole corpus and the merged
ranking is comparable by construction rather than by stapling per-bundle lists
together. The engine is **named**, not inferred: `:index`, because a long-lived
server amortizes a build over every keystroke where a one-shot CLI cannot, and
because the browser's own MiniSearch is a port of it, so a palette hit and an
in-page search rank alike. Results are capped at 50 and the answer reports its
own `total`, so a truncated list never reads as a complete one.

# One palette, every mode

`Cmd/Ctrl-K` (or the rail button) opens a command palette in **every** mode —
hub, single bundle, static render. It began as the hub's bundle switcher, gated
on the hub's presence, which left the two modes most people meet first with no
palette at all; now the palette is universal and *bundles* are the group that
comes and goes. Under a hub, each `App` is built carrying the *other* bundles as
siblings: bundles lead the list and own the empty box, `Cmd/Ctrl-Enter` opens
one in a new tab, and a count badge advertises the palette until it has been
opened once.

Where the hub also answers `/search`, a third group appears: **Concepts**, every
match in every hosted bundle, fetched as you type and shown with its bundle, its
type, and a snippet with the matched terms marked. It comes **last** on purpose.
It is the one group that arrives asynchronously, and a group that lands above the
cursor moves the row under the reader's fingers between the keystroke and the
Enter; last means results can only ever appear below what is already selected. A
hit in another bundle is a page load carrying `?select=<id>` and nothing else —
the view and layout a bundle switch preserves are exactly what naming a node has
to override — while a hit in the bundle already open is selected in place, since
a page load to arrive where you already are throws away the camera and the
filters for nothing. Standalone and static have no `SEARCH_ENDPOINT` at all, so
the group does not exist there rather than existing empty.

Views ride underneath, each carrying the rail's own icon and label
— read from the rail, so the two cannot drift — and where there is no hub, views
become the whole list. What never appears is a dead end: a standalone page
injects an empty sibling list, so the palette offers a bundle only where its
host can answer with one — the same one-template-two-modes discipline `EMBED`
follows.

The keyboard reaches the rest of the page the same way: `/` focuses the current
view's search where it has one, and `?` answers with a sheet of every binding —
reachable from a rail button too, because a shortcut list you can only open with
a shortcut helps whoever needs it least. The sheet is written against the key
handler it documents, so it cannot drift from what the keys do.

# The registry, on the page

`/b/` answered "which bundles are there?" for anyone who knew `/b/` existed, and
grew forms to change them. The ⚙ in the rail asks the same question where the
reader already is: a **Bundles** slide-over
listing every registered bundle with its size, its health as a word, and which
one `/` opens — plus, per row, a `⋯` carrying *Make default*, *Rename…* and
*Remove…*. Rename and Remove take the row over and state themselves; a removal
says the one thing a reader actually fears is not going to happen ("the folder
stays where it is").

There is no **Add**. Registering means naming a filesystem path; a browser
cannot hand one over — the File System Access API yields an opaque handle, never
a path, and is Chromium-only — and it is the agent's act anyway. The footer says
where it is done rather than leaving the absence to be noticed.

The panel reads `GET /bundles` on every open rather than baking the list into
the page, because the hub re-reads the registry per request: a rename made in
another terminal shows the next time it is opened. Writes POST the
`/registry/<verb>` routes and the hub answers with the outcome as data. For a
while `/b/`'s forms posted those same four routes, and two implementations of one
contract is the thing that drifts — so the forms came out, and `/b/` kept the
jobs only it can do (the list, the landing, the way back from a 404, and the
empty state a hub with no bundles has no graph page to show).
Every gate is the server's — the page only renders what it decides, and
`MANAGE_TOKEN` is null wherever a write would be refused anyway, so the page
holds no credential it cannot use. Read-only is explained rather than hidden:
the same facts, no `⋯`, and one sentence naming what decides it.

One bug is worth keeping named, because it is latent for any panel added later.
A slide-over parked at `translateX(100%)` **still occupies layout**, and `#views`
did not clip — the Filters panel only escapes it because `#stage` does. Closed,
the panel widened the document by its own 340px; mid-slide it did the same. Both
halves are fixed (`hidden` while closed, `overflow:hidden` on `#views`) and both
are pinned by a spec that samples `scrollWidth` across the whole animation.

# The box filters, the palette finds — and the box now says so

Two surfaces looked alike and meant different things. The topbar box *filters*
what is on screen; `⌘/Ctrl-K` *finds* across every bundle a hub hosts. The box
carried neither fact: it said "search concepts…", emptied the graph in silence
when nothing matched, and never mentioned the palette — so a reader whose word
lived in another bundle got a blank canvas and no exit. The TUI already
escalated a local miss into a global search; the page did not.

Three additions close it, all inside the box. A **chip** carrying the chord
(`⌘K` / `Ctrl-K`, OS-aware) names the palette where the disappointment happens,
and opens it. A **live count** (`7/8`) makes an empty result a number that
reached zero rather than a view that went blank — the difference between
"nothing here" and "something broke". And on zero, a **panel** says which bundle
and which query came up empty, then offers the way on: `⏎` hands the query to
the palette prefilled and already searching, `esc` clears the box.

The counts come from two directions because the views do. The graph has already
decided by the time `applyGraphFilter` returns, so its count is read live off
Cytoscape with that function's own skip predicate; the catalog and the file tree
resolve asynchronously, so each reports from inside its own render. Only the
views with a search box are counted, and tags is named out of that set — its
cloud is not a list of concepts.

The panel is honest about where it is. Only a hub can answer about every bundle,
so only there does "Search every bundle" exist; on a standalone server or in a
static `okf render` file the panel still names the dead end and offers `esc`,
which is the half of the fix that was never about hubs.

The escalation fires rarely, and that is the design working rather than failing:
the box's index reaches full bodies wherever the page holds them, so most real
words match *something* locally. It is the dead end that needs an exit.

# The search box is full-text, and client-side

The one search box is backed by a full-text index —
[MiniSearch](https://github.com/lucaong/minisearch), lazy-loaded on first focus
and pinned to the same `7.2.0` the Ruby [`minifts`](search.md) port tracks, so an
`okf search --engine index` result and the browser's rank identically. It indexes title, id,
type, tags and **description** in every mode, plus each concept's **body**
wherever the page already holds it: `okf render` bakes every body in, so a static
file searches bodies offline; the live server keeps bodies lazy, so its index
stays metadata-only until a backend body index arrives. Matches are ranked,
multi-term (`AND`), prefix (as-you-type) and typo-tolerant, and drive the graph,
catalog and files views alike; a second index covers each `index.md`/`log.md`
**body**, not just its filename, so the tree's authored rows are searchable on
what they say. Until an index loads —
or if the CDN is unreachable — each view falls back to its own substring filter,
so the box is never dead. **The browser and the CLI diverge again by default, and
this time on purpose.** The gap was once accidental — the CLI a substring scan,
the browser fuzzy, two implementations nobody had reconciled — and the `minifts`
port closed it by making both run one engine. [`search`](search.md) has since
made the scan its default, which reopens the gap deliberately: the two surfaces
have different lifecycles, and the reason is the difference. A page holds its
index across every keystroke, so a build amortizes over hundreds of queries; a
CLI process builds, asks once, and exits. `okf search --engine index` is the
setting where both run the same BM25+ arithmetic and rank alike — the route to
take when reconciling a CLI answer with what the page shows.

The behavioural split follows the reader, not just the arithmetic. The browser
searches as you type and forgives typos because a human wants the near miss; the
CLI matches raw text exactly because an agent citing a row wants the identifier
it typed, backticks and dots intact.

# Links navigate in-app; the graph has a second mode

Relative Markdown links inside the inspector, the files preview, and the Index
panel resolve against the open concept and navigate **in-app**: a link to a
concept selects its node, a link to an `index.md` or a bare directory opens that
directory's map, and a link to a `log.md` opens the history — reserved files used
to strike through as dead, and now every cross-reference between maps navigates.
External links open in a new tab, and links that would leave the bundle are
disabled: the page never serves a 404 from a body link. A **file-tree mode** on
the toolbar redraws the bundle as folders-become-nodes with only folder→child
edges — the acyclic layered tree of the files, next to the emergent link graph.

Beside it, **show indexes** draws the §6 map as a layer of its own, under
*whatever* layout is running rather than only inside the tree. Each `index.md`
becomes a tile edged to the concepts it lists and to the maps beneath it. It
shares one *selector* with file-tree mode's folder node, because the two are the
same thing twice over — clicking either opens that directory's `index.md` — so
they converge on one look rather than parting by mode: an accent square with
dashed edges into it, never a concept's circle. Colour separates **kinds** here
rather than modes, which is what it should have been doing all along: a directory
is not a concept and should not read as one. Authorship then shows as form —
solid where an author wrote a map, hollow and dashed where the bundle only
implies one. That makes the toggle a curation read as
much as a navigation one, since a field of outlines is a directory that never got
a map. File-tree mode
already draws folders, so it disables the toggle rather than doubling it.

Moving between the modes is one click, which took fixing twice over. Tearing the
layer down ran its own layout while file-tree mode ran `breadthfirst` a beat
later — two layouts racing the same canvas, so the tree landed wrong until it was
clicked again; a `relayout` flag now lets a caller say it owns the layout. And
because the layer is built from a `fetch`, each toggle takes a ticket: a promise
whose ticket is stale, whose toggle has since flipped, or that resolves inside
file-tree mode does not land.

Those nodes are **drawn, never modelled**. `index.md` is reserved — it is not a
concept — and the page must not be the place that quietly decides otherwise, so
they are built from `/index` straight onto the canvas and `NODES`, `/catalog` and
the type and tag indexes never learn they exist. A type or tag filter passes them
over for the same reason (a map has neither), but a map whose concepts are all
filtered away leaves with them: the phantom-empty-box rule, applied deepest-first
so a parent map survives on a surviving child.
The inspector and files panes are drag-resizable (persisted; double-click resets),
and the inspector boots hidden on every screen until the first node tap.

**Cluster mode nests.** A cluster is a directory of concepts, and the boxes nest
as the directories do, to a depth the reader picks beside the layout select
(`1` by default — exactly the flat one-box-per-first-segment view the mode always
drew; a flat bundle is offered no control at all, since there is nothing to
choose). At depth *N* every directory of depth ≤ N gets a box, intermediates that
hold no concepts of their own included, and a concept attaches to its own
directory's box truncated to N. The root box is the exception that stays: it
holds direct-root concepts and never nests another. Box ids carry the directory
verbatim (`box::platform/services`, `box::.`), so a tap resolves to a map with no
label to unmangle — and `box::` rather than `dir::`, which file-tree mode's folder
nodes already own.

A filter or search that empties a directory hides its **box** too, rather
than stranding a labelled empty rectangle: the filter recomputes each compound
parent from its surviving **leaf** descendants — children alone would read an
intermediate box holding only sub-boxes as empty and take the whole branch below
it off the canvas — and clustering re-applies the active filter
before the layout tiles the boxes, so the two orders — filter-then-cluster and
cluster-then-filter — agree. Selection clears with `Esc` as well as a tap on
empty canvas, because a dense graph leaves almost no empty canvas to hit.

# One page, from a phone to a desktop

At `≤768px` — phones and portrait tablets — the topbar tools fold into a `⚙`
sheet, panels go full-bleed, the file list collapses to its tab bar, and the graph
fits itself after load. The sheet shows when a filter is active, so a control
folded out of sight can never silently narrow what the graph is showing.

The breakpoint tracks the width actually available to the chrome, not a device
class, which is why rotation is a re-evaluation rather than a one-way door: the
same tablet crosses back over `769px` in landscape and gets the desktop layout,
and `orientationchange` refits the graph to its new box.

## On a touch screen a tap opens a card, not the inspector

"Panels go full-bleed" was the takeover, and it cost the graph outright. At this
width `.graph-body[data-side=default]` is `grid-template-columns:0 1fr`, so the
moment a dot was tapped `#stage` measured **0 px wide**: the graph was not
covered by the inspector, it was gone. Exploring a phone became open → read →
close → tap the next dot, and there was no way to see a concept and its
neighbourhood at once — which is the one thing a graph is for.

So on a touch screen a node tap raises a **preview card** at the bottom edge
instead. It carries the concept's head — type, title, description, `N links out ·
N in` — over a graph that keeps every pixel and stays pannable, zoomable and
tappable. Drag it up for the neighbourhood lists and the body; tap a row in one
and the card's contents swap **in place** while the camera walks to the new node.
Three snap points, reachable by drag, flick, tap or arrow key.

Two behaviours are the point of it, and both are subtractions:

* **Nothing animates.** The card had a 0.26 s entrance. Exploring a graph is
  dozens of taps, and every one of them charged that wait. It was removed
  outright — no transition, no `requestAnimationFrame` staging, no close timer —
  so the card takes exactly **one transform value for its whole life on screen**.
  Dragging still moves it directly; that was never a transition.
* **A miss on bare canvas does not dismiss it.** It used to, on the reasoning
  that the gesture means "never mind". The dots are small at this size and the
  misses are constant, so the card kept vanishing by accident and the next dot
  replayed the entrance from scratch. That pairing is what turned exploring into
  a slideshow, and it also explains why the same code felt fine on a tablet:
  dots far enough apart that the miss rarely fired. Dismissing is explicit — `✕`,
  a downward swipe, or `Esc`.

The camera aims at the middle of the **visible band** — canvas top to card top —
rather than at the canvas centre, which would park the selected node underneath
the card describing it, and it skips the move entirely when that band is under
140 px, so the view never jerks for a node nobody can see.

The card's branch is deliberately **wider than the chrome's**: `≤768px`, *or*
`≤1024px` in portrait. A portrait tablet keeps the rail and the desktop topbar —
it has the room — but zero-width-stage is its bug too, and a bottom card is the
right gesture on any touch screen held upright. Rotate it to landscape and the
inspector comes back. The rail only folds at 768 px, so on that tablet the card
starts at `left:76px`: one that buried the Stats rail item under itself would be
the takeover again, just shorter.

# The graph opens the page, and a note says the index is there

A bundle read as documentation has to answer "where do I start?", and a field of
unlabelled dots does not say it on its own. The page still **opens on the graph**
— that constellation is what makes a bundle legible at a glance, and it is the
one view that reads well at every width. What the graph cannot say is that the
bundle has an index, so a **dismissible note at the bottom says it once**: what
the picture is, how to touch it, and that the index exists. **Read the index**
takes the reader straight there; `✕` and the button both remember the dismissal
in `localStorage`, so a returning visitor never sees it again.

Landing on the index instead was tried and reverted. It read well on a wide
window and badly everywhere else: a phone got a wall of prose where the
constellation should have been, and every visitor — first or five-hundredth —
paid for an introduction only the first one needed. A note costs one visit; a
landing costs all of them.

The note belongs to the graph (`#app:not([data-view=graph]) ~ #hello`, a
**sibling** combinator, because it sits outside `#app` with the other fixed
overlays) so it never floats over a reader, and it absorbed the old mobile-only
tip rather than stacking a second banner beneath it.

## The wording follows the device on two gates, not one

Width answers neither question on its own. What a reader **does** follows
`(pointer:coarse)` — a touch tablet in landscape is wider than 768px and still
taps; a narrow desktop window is narrower and still clicks. What a reader can
**reach** follows `(max-width:768px)` — `☰` exists only once the rail collapses,
so promising it at any other width is a lie. A pointer-less environment matches
neither and keeps the click wording, which is the safe default. `(max-height:480px)`
tightens the setting, and short *and* wide puts the question beside the button so
the card spends width instead of height — a landscape phone went from half the
screen to under a third.

## A second beat, where the menu is the only way through

On a compact layout the rail is folded behind `☰`, so a reader who has just left
the graph cannot see where the other views went. A second, lighter note says so
— anchored **under the button it is about**, with a caret pointing at it, because
a bottom sheet naming a top-left control asks the reader to do the mapping.

It fires on *leaving the graph* by any route rather than off the first note's
button, so the reader who dismissed that note and found their own way still gets
told. Opening `☰` answers it — but only when the note is actually on screen: `☰`
is the only way off the graph there, so the first tap always *precedes* the note,
and marking it done then would burn the flag on a hint nobody saw. It carries its
own `localStorage` key, so dismissing one is not dismissing both.

Both notes are the same guide speaking, and share a vocabulary by sharing
selectors rather than by resembling each other: one rule draws the three node
dots, one dresses both buttons. Ink-on-background rather than the accent is the
only pairing that clears 4.5:1 in **both** themes, which leaves the dots as the
one piece of colour in either card. Everything is written for a finger: a
first-time reader on a phone is the least oriented person the page ever serves,
and "click" means nothing to them.

**Read the index** opens the index. That reads as tautology and was a bug: it
called the action that opens the *panel listing* the indexes, which lands on
"Pick a file on the left" — a button that names a destination owes the reader
the destination, not the drawer it lives in.

Deep links are unaffected, and `?select=`/`#hash` now name a view as well as a
node — selecting into a graph nobody is looking at is a silent no-op, and
`setView` returning early when the view is already current makes that free.

# The browser shows the authored layer, not just derived views

The graph, catalog, files, tags, and stats panels are all *derived* from the
model; the one layer humans actually write — the §6 index map and the
[§7 log](../format/okf-format.md) — now renders in the browser too. The tree
column is **one tree**. The authored files used to live on a second tab as a
flat list of paths, which put a directory's own map somewhere other than the
directory — the one place a reader looks for it. `index.md` and `log.md` are rows
now, at the top of the folder they document, above its subfolders and concepts,
and **Indexes only** is a toggle that narrows the same tree to them. Narrowed,
a folder owns exactly one row, so its header becomes a line of chrome per map —
the row stands where the header stood instead, at that folder's depth and
carrying the path. That is the flat list the tab used to show, with the nesting
still legible in the indent. One row renderer serves both shapes; only the label
differs (bare filename inside its folder, whole path when it stands in for one),
so a click behaves identically either way. The toggle yields only when it would hide what was
just opened: a map is right there in the filtered list, so opening one leaves it
alone — browsing the authored layer must not destroy the list being browsed — and
a concept cannot appear under it at all, so following a link to one releases it
rather than leaving the reader's selection invisible. A **log** offers no graph
button: it is a chronology, not a place in the graph, and the button is hidden
rather than disabled because it is never applicable, not merely unavailable now.
(It was worse than dead: a log's directory is the root, so it opened the *root
index's* node.) The type and tag combos hide reserved files while they are
set — a reserved file has neither, so a filter about concepts is not a statement
it can answer.

That also retired the last fiction in the rail. **Index** was a rail item with no
`#view-index` behind it, just the files view showing its other tab, so
`activeRail()` had to answer a question of view *and* tab. The item is still
there — it is the fastest way to the one page written to be read first — but as
an **action**: it opens the root map, exactly as the first-visit note's button
does, through the same `readIndex()`. `activeRail()` answers with the view it
lands on, so **Files** highlights and nothing has to invent a place for Index to
be. `?view=index` resolves to that action too, which is what the deep link
shipped in 1.8.0 always meant.

The bundle names its own root. `(root)` and `/` are what a filesystem calls it,
not what a reader does, so the tree's root row, file-tree mode's root node, the
index layer's root map and the inspector's directory map all carry the name the
header already shows — `--title` included, so a named server labels the root with
that name. The row is set as a name rather than a path segment: no uppercasing,
and truncated rather than wrapped, since a title has no length limit. What keeps
its own `(root)` is the **dir** vocabulary the page shares with `okf dirs` and
`okf stats`: `.` is the stored value everywhere — chip values, box ids, JSON —
and `(root)` is only ever the label a human reads. A UI name and a data spelling
that happened to read alike, and only one of them was being renamed.

The tree is a real explorer — directories *nest*, one
row per path segment indented by depth, so `core/configurations` sits inside
`core` instead of standing beside it as a sorted full path did, and closing a
folder takes its whole subtree with it (foldable whether or not a search is
narrowing them, with a fold/unfold-all control in the tree header; a collapsed
group still shows its header, so it never hides a match, and a folder that holds
nothing but folders still renders, or the chain to its children would break).
The fold controls read every folder in the tree rather than the ones on screen,
and they treat the root as not theirs to fold: "collapse all" folds everything
*inside* it and leaves the root open, because folding the root too answers the
click with a lone `(root)` row and hides the top-level folders — the one thing a
reader wants left standing after collapsing everything. Unfolding clears the
whole set, root included, so a root closed by hand is still reversible from
there.
Folder nodes in file-tree mode and directory boxes in cluster mode are
clickable: the inspector opens that directory's map, the authored `index.md` or a
synthesized listing badged as such when none exists; **Open in graph** — one label on
every file, because the question is the same whatever is open — shows a map *in*
the graph: it switches the **index layer** on
rather than file-tree mode, so the layout the reader chose survives, and the
map is emphasised exactly as a concept is — one `focusNode` serves a concept, a
folder node and a map, because selection should mean the same thing on this
canvas whatever was selected. A reader already
in file-tree mode stays there and focuses the folder node, because that view is
the map. The toggle hands back a promise for it, since the layer is fetched and
the node has to exist before it can be highlighted. The log is read **live from disk** on every open, so an entry a `maintain`
pass just appended shows without a restart. This closes the parity gap from the
other side of [search](search.md): the CLI's [`index` map](read-views.md) had no
browser twin, just as the browser's search had no CLI verb — now each medium shows
both.

# Request flow

```mermaid
sequenceDiagram
  participant B as Browser
  participant A as okf server (Rack app)
  B->>A: GET /
  A-->>B: HTML page + inlined minimal graph data
  Note over A,B: angle brackets escaped (json_for_script) — safe
  B->>A: GET /node?id=… (on demand)
  A-->>B: concept Markdown body
  Note over A,B: marked renders it, DOMPurify sanitizes it — safe
```

# Endpoints

| Path | Serves |
|------|--------|
| `/` | the HTML page (graph + inlined minimal data) |
| `/node?id=` | one concept's rendered body |
| `/node/meta?id=` | one concept's metadata |
| `/catalog`, `/tags`, `/types` | the JSON behind the browser panels |
| `/index` | the §6 map behind the tree's `index.md` rows (boot snapshot) |
| `/log` | every `log.md`, read live from disk for the Log |

Under a hub every path above keeps its shape, mounted under its bundle's prefix
(`/b/<slug>/node?id=`), plus the hub's own:

| Path | Serves |
|------|--------|
| `/` | redirect to the default bundle (empty-state page when none) |
| `/search?q=` | ranked concepts across every hosted bundle (JSON) |
| `/b/` | the [bundles list](bundles-manager.md) |
| `POST /registry/{default,rename,remove,add}` | the manager's four writes |

# Responses are gzipped on the wire

Under `okf server`, every response is gzipped when the client accepts it:
`Rack::Deflater` wraps the app at the boot seam — `serve`, the one path *both* a
single bundle and a [hub](../registry.md) pass through — so the browser
decompresses transparently and the heaviest payloads — the inlined minimal graph,
the full-body JSON — cross the wire at a fraction of their size. Putting the wrap
at the shared seam rather than in either mode is what makes it total: a mode added
later gets compression for free, and neither mode can forget it. The wrap is boot
policy, not part of the app: a host that mounts `OKF::Server::App` brings its own
compression, and `okf render`'s static file carries none (whatever hosts it
compresses instead). It costs [no new dependency](../design/runtime-dependencies.md) —
`Rack::Deflater` ships inside the `rack` the gem already requires — and a client
that sends no `Accept-Encoding` (plain `curl`) still gets an identity response.

# Trust boundary

Both paths into the page are guarded. Inlined data goes through `json_for_script`,
which escapes `<` so it cannot break out of its `<script>`; each fetched body is
run through `DOMPurify.sanitize(marked.parse(...))`, which strips any script or
handler before it reaches the DOM. See the
[server trust boundary](../design/server-trust-boundary.md) for what that does and
does not cover.

# Citations

[1] [lib/okf/server/app.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/server/app.rb) — the Rack app and its routes; `GET /` renders the page through [`OKF::Render::Graph`](render.md).
[2] [lib/okf/cli/server.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli/server.rb) — the `serve` boot seam that wraps every served app in `Rack::Deflater` (the static counterpart, [`render`](render.md), is its own capability).
[3] [lib/okf/server/hub.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/server/hub.rb) — the multi-bundle dispatcher: the `/b/<slug>/` mounts, the default redirect, and the hub's own index, empty-state, and 404 pages.
[4] [lib/okf/render/graph/template.html.erb](https://github.com/serradura/okf-gem/blob/main/lib/okf/render/graph/template.html.erb) — the page itself: the two MiniSearch indexes behind the search box, the compound-parent visibility pass that keeps emptied directory boxes off the canvas, and the file tree's fold controls.
