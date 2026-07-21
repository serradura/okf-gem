# What the suite covers, and what it does not — the per-contract map

This is the coverage map for `test/browser/`, measured against the graph page's
own history. It is a **per-contract, checkable enumeration**: every user-visible
behavioral contract the page (`lib/okf/render/graph/template.html.erb`)
introduced across its 49-commit history, each marked covered / partial /
uncovered against a named spec. Read it as a map, not a score — it tells you
exactly what is proven and exactly what is still open.

It was built by reading all 49 template commits (message + diff, across the two
file renames) and cross-referencing the 23 spec files. The **Uncovered worklist**
at the bottom is the ranked to-do list; the per-area tables are the evidence.

---

## Headline numbers

Reading the 49 commits yielded **204 raw behavioral contracts**, **54** of them
regression-fixes. After removing the superseded ones (reverted or replaced later
in history — the Index-view→tabs→tree arc, the reverted landing page, the
index-layer accent flip-flop, the 5× number-key remaps, the `#mnote` note folded
into `#hello2`), **208 net-live contracts were rowed** in the area tables below
(superseded micro-contracts are summarised, not individually rowed; A7-10 is kept
as a rowed ⊘ because it read as a live gap until the history was checked).

Work landed since then is rowed the same way, with `(name)` in the commit column
rather than a hash — the search bridge (A3-20…29), the Bundles panel (A8-17…33)
and the touch preview card (A6-15…33) — which brings the map to **227 rowed
contracts**. A feature is not done here until its rows are in this table.

**Coverage of those 227 net-live contracts (tallied from the tables, they sum
exactly):**

| | Count | % |
|---|---:|---:|
| ✓ covered | **222** | 98% |
| ~ partial | 1 | <1% |
| ✗ uncovered | 4 | 2% |

The **4 uncovered** rows are what is left after Priority 1 (cleared), every
Priority-2 row outside the command palette (✓), and all of Priority 3 (✓) — the
last on the strength of three purpose-built fixtures (`fixtures/tree`,
`fixtures/manytags`, `fixtures/deeppath`), each on its own port and static page
like `fixtures/hostile` so none touches the flat 8-concept fixture's counts. A
tier once filed as hard fell to emulation and route interception with no fixture
at all — reduced-motion, fuzzy search, the CDN-fail cose fallback, the coarse-
pointer wording and short-viewport reflow, the diagram cursor/hover, and the
server-only body/log re-fetch and stale-`/index` drop. The full breakdown of
what is closed and why the 4 that remain are blocked is in
[How to drive this to full coverage](#how-to-drive-this-to-full-coverage) at the
bottom; in short, of the 4 ✗: 2 have no deterministic handle (A2-26 an
absence-proof, A2-37 node non-overlap), and 2 are palette rows — A8-12 (needs a
20+ bundle hub so the initial list overflows, and even then the active row is at
index 0) and A8-16 (an unbuilt feature). The 1 remaining `~` is A2-25, whose
map-visibility observable A2-24 already owns.

### By area (covered / partial / uncovered)

| Area | ✓ | ~ | ✗ | Total |
|---|---:|---:|---:|---:|
| 1 — Boot, views, rail, view-switching, keyboard | 11 | 0 | 0 | 11 |
| 2 — Graph canvas, camera, layout, emphasis, cluster/tree/index-layer | 35 | 1 | 2 | 38 |
| 3 — Filters & search | 29 | 0 | 0 | 29 |
| 4 — Inspector, links, escaping/sanitization | 20 | 0 | 0 | 20 |
| 5 — Files view, file tree, reserved files | 28 | 0 | 0 | 28 |
| 6 — Mobile / responsive, touch preview | 33 | 0 | 0 | 33 |
| 7 — First-visit notes | 9 | 0 | 0 | 9 |
| 8 — Command palette, hub, help, keyboard sheet | 31 | 0 | 2 | 33 |
| 9 — Deep links, theme, splitters, diagram, static/server, interiors | 26 | 0 | 0 | 26 |
| **Total** | **222** | **1** | **4** | **227** |

**Every area but 2 and 8 is now fully covered** (0 ✗, 0 ~). The 4 remaining ✗ sit
in just those two: **Area 2 (2 ✗)** — A2-26 (absence-proof) and A2-37 (node
non-overlap, no deterministic handle); **Area 8 (2 ✗)** — A8-12 (needs a 20+
bundle hub, and even then near-vacuous) and A8-16 (an unbuilt feature). The one
`~` is A2-25 (Area 2), whose only observable A2-24 already owns. Every one is a
documented blocker, not an unwritten test — see the worklist.

### The two counts, reconciled

An earlier version of this file measured **regression-fixes only** and reported
~50 of ~94. This version counts **all contracts** — features and regressions —
and classifies conservatively (ambiguous → FEAT), which is why its raw REG count
(54) is below that earlier 94: the old count split the big commits (ed6c0af,
adf96ff, 4f4aae4) into finer regression rows and counted some behavior-changing
features as regressions. **Neither is wrong; they measure different things.** The
page reads as "better covered" here (75%) precisely because features — many of
them covered — are now in the denominator. What matters below is the concrete ✗
list, not the denominator.

**Caveats:** the REG count is a floor (ambiguous→FEAT); superseded contracts are
excluded; coverage at the edges is a judgment call (`~`); some ✗ contracts have
no cheap external handle (fullscreen, CDN-failure fallback, reduced-motion,
count-up, pure visual polish) and need instrumentation, a new fixture, or media
emulation — each flagged in the worklist.

## Legend

`Type`: REG = regression-fix, FEAT = feature. `Cov`: ✓ covered · ~ partial ·
✗ uncovered · ⊘ superseded (excluded). `Spec` cites the covering test
(`file › title`) or the reason it is uncovered.

## Path eras (for `git show`)

- `lib/okf/server/templates/graph.html.erb` — d942471 → d1b485d
- `lib/okf/server/graph/template.html.erb` — 30786af → 76e4a97
- `lib/okf/render/graph/template.html.erb` — bf3bd61 → HEAD

`git show <hash> -- <all three paths>` shows the right diff in every era.
Commits with **no page-behavior contracts**: 8dbdbd2, b4e01f9, 30786af (OG/meta),
76e4a97, bf3bd61 (refactor/move), e0170e0 (test-only).

---

## Area 1 — Boot, views, rail, view-switching, keyboard

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A1-01 | cc7d545 | REG | Boots on the Graph view (reverted the index landing) | `#app[data-view=graph]`, `let view='graph'` | ✓ | boot › lands on the graph |
| A1-02 | d942471 | FEAT | Rail switches views, one active; `#view-*` toggles | `.rail-item.active`, `#app[data-view]` | ✓ | views › the rail moves #app[data-view] |
| A1-03 | d942471 | FEAT | Each view populates rather than staying on its loader | `#cat-cnt`, `#view-stats`, `#ftree-list` | ✓ | views › each view populates |
| A1-04 | 1093ae3 | REG | Number keys 1graph 2files 3catalog 4tags 5stats; 2=index→files | `VIEW_KEYS`, keydown | ✓ | views › the number keys reach the same six views |
| A1-05 | a2f6db1/1093ae3 | REG | Index rail item resolves to Files with root map open | `readIndex()`, `activeRail()` | ✓ | views › Index lands on Files |
| A1-06 | d942471 | REG | A number key typed into a text field is text | keydown guard on input focus | ✓ | views › a number key typed into a text field |
| A1-07 | d942471 | FEAT | `/` focuses the view's search (not on Stats) | `SEARCH_PH`, keydown `/` | ✓ | help › / focuses the search |
| A1-08 | d942471 | FEAT | `0` fits the graph (graph view only) | keydown `0` → `fitGraph` | ✓ | graph-modes › the 0 key fits the graph |
| A1-09 | d942471 | FEAT | `\` toggles the inspector | keydown `\` → `setSide` | ✓ | inspector › the \ key toggles the inspector |
| A1-10 | d942471 | FEAT | `f` toggles fullscreen | `#btn-full`, `requestFullscreen` | ✓ | graph-modes › the f key requests fullscreen on the app element (spy on requestFullscreen — the page's contract is that it *asks*; real fullscreen is the browser's job, unreliable headless) |
| A1-11 | d942471 | FEAT | Reduced-motion disables transitions/count-up | `@media (prefers-reduced-motion)` | ✓ | boot › reduced motion strips the graph body's transition (emulateMedia flips it live; transitions only) |

## Area 2 — Graph canvas, camera, layout, emphasis, cluster/tree/index-layer

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A2-01 | d942471 | FEAT | Clicking a node selects: dim others, hl node+neighbourhood, open inspector, write hash | `.dim`/`.hl`, `location.hash` | ✓ | inspector › clicking a node; emphasis |
| A2-02 | 8ca455f | REG | Esc clears selection: drop dim/hl, forget hash | `deselect()`, keydown Escape | ✓ | inspector › Escape drops the selection |
| A2-03 | 138b705 | REG | `.dim`/`.hl` outrank a tree edge's own opacity (style array order) | `.dim` after `edge.tree` | ✓ | emphasis › dim outranks a tree edge |
| A2-04 | 138b705 | REG | `.dim` outranks an index-layer edge's opacity | `.dim` after `edge.ixe` | ✓ | emphasis › dim outranks an index-layer edge |
| A2-05 | 975a522 | REG | Cluster-mode selection stays legible (dim leaves/edges, never `:parent`) | `focusNode` `.not(':parent')`, effectiveOpacity | ✓ | emphasis › selection stays legible in cluster mode |
| A2-06 | d942471 | FEAT | Selected node carries the highlight border | `.hl` border-width/color | ✓ | emphasis › the selected node carries the highlight border |
| A2-07 | 9158ca6 | REG | One `focusNode` drives concept/folder/map emphasis identically | `focusNode(ele,opened)` | ✓ | emphasis › concept + tapping a folder/map node (all three paths) |
| A2-08 | 9158ca6 | REG | Tapping a folder (`.dir`) node emphasises it (dim rest+hl) | tap handler `.hasClass('dir')`→focusNode | ✓ | emphasis › tapping a folder node in tree mode |
| A2-09 | 9158ca6 | REG | Tapping a map (`.ix`) node emphasises it | tap handler `.hasClass('ix')`→focusNode | ✓ | emphasis › tapping a map node in the index layer |
| A2-10 | d0b4fed/9158ca6 | REG | Opening a map in-graph (non-tree) emphasises it like a concept | `setIxNodes(true).then(focusNode)` | ✓ | indexes › opening a map in the graph draws the index layer and emphasises the map |
| A2-11 | d942471 | FEAT | Cluster wraps areas in one compound parent each | `:parent`, `#btn-cluster[aria-pressed]` | ✓ | graph-modes › cluster wraps the concepts |
| A2-12 | d942471 | FEAT | Cluster undoes itself completely | `setClustered(false)` | ✓ | graph-modes › cluster undoes itself |
| A2-13 | d942471 | FEAT | Cluster disables the layout selector | `layoutSel.disabled` | ✓ | graph-modes › cluster disables the layout selector |
| A2-14 | 8ca455f | REG | A cluster box whose concepts are all filtered is hidden | `:parent` `display:none` in applyGraphFilter | ✓ | graph-modes › clustering re-applies the active filter, and an emptied area box hides |
| A2-15 | 8ca455f | REG | Clustering re-applies the active filter before tiling | `setClustered`→`applyGraphFilter` first | ✓ | graph-modes › clustering re-applies the active filter, and an emptied area box hides (filter set before clustering still takes) |
| A2-16 | ed6c0af | FEAT | Tree mode: folders-as-nodes, folder→child edges only, link edges hidden | `#btn-tree`, `node.dir`, `edge.tree`, `edge.linkhid` | ✓ | graph-modes › tree mode adds folder nodes and undoes |
| A2-17 | ed6c0af | FEAT | Tree and cluster are mutually exclusive; tree disables layout+cluster | `setTree`↔`setClustered` guards | ✓ | graph-modes › tree and cluster are mutually exclusive — entering tree drops and disables cluster |
| A2-18 | ed6c0af | FEAT | Folder nodes are unselectable and filter-exempt | `hasClass('dir')` guards | ✓ | graph-modes › a folder node is unselectable and exempt from the graph filter |
| A2-19 | 1498a7c | REG | Tree folder nodes render as accent squares (like maps) | `node.dir,node.ix` background accent | ✓ | graph-modes › tree edges render dashed and folder nodes carry the accent |
| A2-20 | 1498a7c | REG | Tree parent→child edges are dashed | `edge.tree` line-style dashed | ✓ | graph-modes › tree edges render dashed and folder nodes carry the accent |
| A2-21 | aeef15b | FEAT | `#btn-ix` draws the index layer over any layout, flips pressed | `#btn-ix[aria-pressed]`, `cy.nodes('.ix')` | ✓ | graph-modes › the index layer adds the map nodes |
| A2-22 | aeef15b/456aa79 | FEAT | Authored map draws accent, synthesized faint+dashed | `node.ix` vs `node.ix-syn` | ✓ | index-layer › a synthesized map node is filled fainter than an authored one (opacity .2 vs .9) |
| A2-23 | aeef15b | FEAT | Index edges dashed `.ixe`; synth `.ixe-syn` fainter | `edge.ixe` .5 vs `edge.ixe-syn` .3 | ✓ | index-layer › synthesized map's edges fainter |
| A2-24 | aeef15b | FEAT | A map with all concepts filtered hides; parent survives on a child | `ixVisibility()`, node `display` | ✓ | index-layer › a map whose concepts are all filtered away |
| A2-25 | aeef15b | FEAT | Index nodes are exempt from the graph filter | applyGraphFilter skips `.ix` | ~ | index-layer (ixVisibility). The raw per-node `.ix` skip has no observable distinct from A2-24: whatever the filter leaves, `ixVisibility()` then hides a map with no surviving child, so a map's visibility is A2-24's contract, not this one's. |
| A2-26 | aeef15b | FEAT | Index nodes never modelled (absent from catalog/tags/types) | id prefix `ix::` | ✗ | not asserted absent from catalog |
| A2-27 | aeef15b/456aa79 | REG | Entering tree disables `#btn-ix` and tears down the layer | `#btn-ix[disabled]`, `setTree`→`setIxNodes(false)` | ✓ | graph-modes › entering tree mode disables the index button and tears down the layer |
| A2-28 | 456aa79 | REG | index→tree switch lands clean in one click (no competing layout) | `setIxNodes(on,relayout=false)` | ✓ | camera-races › index layer to tree mode |
| A2-29 | 456aa79 | REG | A stale `/index` fetch after a toggle/in-tree is dropped | `ixSeq` ticket guard | ✓ | graph-modes › a stale index-layer fetch is dropped when the toggle flips before it lands (route holds /index; server-only) |
| A2-30 | d942471 | FEAT | Layout selector: 5 built-in + 3 lazy, cose fallback on load fail | `#layout`, `ensureLayout` | ✓ | graph-modes › switching layouts keeps nodes + a lazy layout whose CDN fails falls back to cose (route.abort) |
| A2-31 | adf96ff | REG | un-clustering restores the chosen layout (not hardcoded cose) | `cy.layout` name | ✓ | camera-races › un-clustering restores the chosen layout |
| A2-32 | d942471/f00cb66 | FEAT | Fit frames the visible nodes (gentle 450ms ease) | `#btn-fit`, `fitGraph` | ✓ | graph-modes › fit brings the whole graph inside |
| A2-33 | ed6c0af | REG | One camera move per selection (deferred single pan) | `centerOn`, `window.__camCenters` | ✓ | camera-races › a panel-opening click commits exactly one |
| A2-34 | 9ea6162 | REG | fitGraph skips a hidden 0×0 canvas (no collapse-on-return) | `fitGraph` clientWidth guard | ✓ | views › a fit fired while the graph is hidden |
| A2-35 | adf96ff | FEAT | Non-deep-linked graph auto-fits after load + on orientation | `load`/`orientationchange`→fitGraph | ✓ | graph-modes › the graph auto-fits on orientationchange (dispatch the event — the page's contract is to respond to it; load-fit covered by A2-34) |
| A2-36 | adf96ff | FEAT | Zoom floor auto-relaxes so a big graph never grows past fit | `relaxZoom()`, `cy.minZoom` | ✓ | graph-zoomfloor › relaxZoom lowers minZoom below the default (fixtures/biggraph, a 100-node ring; minZoom settles ~0.17 < 0.2) |
| A2-37 | ed6c0af | FEAT | Nodes spaced apart across layouts | layoutOpts nodeOverlap/spacingFactor | ✗ | visual, no clean handle |
| A2-38 | d942471 | FEAT | Stats bars/type-legend clickable → focus that slice in graph | `.bar.clickable`, focusGraphType/Area | ✓ | interiors › clicking a type/area bar |

## Area 3 — Filters & search

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A3-01 | d942471 | FEAT | Hiding a type drops its concepts and the badge counts it | `.chip.off`, `.fbadge` | ✓ | filters › hiding a type drops its concepts |
| A3-02 | d942471 | FEAT | Badge counts every dimension (type/area/tag) | `.fbadge` | ✓ | filters › the badge counts every dimension |
| A3-03 | d942471 | FEAT | Area and type filters intersect | applyGraphFilter | ✓ | filters › area and type filters intersect |
| A3-04 | d942471 | FEAT | A tag spanning two areas selects across both | activeTags | ✓ | filters › a tag spanning two areas |
| A3-05 | d942471 | FEAT | Reset restores every concept, zeroes the badge | clearGraphFilter | ✓ | filters › Reset restores every concept |
| A3-06 | dc83857 | FEAT | Filter-finder box narrows Type/Area/Tag chips together | `#filter-search`, syncFilterChips | ✓ | filters › the filter finder narrows the chip lists |
| A3-07 | dc83857 | FEAT | Tag chips capped at top-40 until the finder reaches all | chipRow tag cap | ✓ | filters-manytags › tag chips cap at 40 until the finder reaches all (fixtures/manytags, 45 tags) |
| A3-08 | d942471 | FEAT | Closing the slide-over leaves the applied filter in force | `#filters` toggle | ✓ | filters › close leaves the applied filter in force |
| A3-09 | 562dba5 | FEAT | One MiniSearch full-text index shared by graph/catalog/files | `ftIndex`, `ftMatch()` | ✓ | filters › narrows the graph to matching concepts |
| A3-10 | 562dba5 | FEAT | Search matches the description, not only the title | `descOf`, boost.description | ✓ | filters › matches on the description |
| A3-11 | 562dba5 | FEAT | Body text searchable only in the static bake | body in index only when baked | ✓ | filters › body text is searchable only in the static render |
| A3-12 | 562dba5 | FEAT | Clearing the search restores every concept | applySearch('') | ✓ | filters › clearing restores every concept |
| A3-13 | 562dba5 | FEAT | A term nothing matches empties the graph | ftMatch empty | ✓ | filters › a term nothing matches empties the graph |
| A3-14 | 562dba5 | FEAT | Search composes with a chip filter | applyGraphFilter ∧ ftMatch | ✓ | filters › search and a chip filter compose |
| A3-15 | 562dba5 | FEAT | Multi-term AND, prefix, fuzzy (typo-tolerant) | searchOptions prefix/fuzzy/AND | ✓ | filters › a one-edit typo still matches — the index is fuzzy (fuzzy asserted in isolation; prefix/AND exercised implicitly by the as-you-type search tests) |
| A3-16 | 562dba5 | FEAT | Substring fallback until the index is ready / CDN down | ftMatch null → includes | ✓ | filters › search falls back to substring matching when the index is unavailable (route.abort MiniSearch; a title substring still narrows) |
| A3-17 | 562dba5 | FEAT | Lazy: index builds on first focus/keystroke | `onfocus`→buildFtIndex | ✓ | filters › the MiniSearch index is built lazily — its script loads only on first search focus (route flag on the CDN: absent at boot, present after focus) |
| A3-18 | dc83857 | FEAT | Catalog filters by area & tag (not just type) + find box | `#cat-fareas`/`#cat-ftags` | ✓ | interiors › the slide-over filters by area and by tag; the find box narrows the chips |
| A3-19 | dc83857 | FEAT | Tags view Types/Areas filter, recounts over survivors | `#tag-filters`, tagMatch | ✓ | interiors › a type filter recounts the cloud over the surviving concepts |
| A3-20 | (bridge) | FEAT | The box carries the palette's chord as a chip, OS-aware, inside `label.search` | `#s-cmdk` | ✓ | search-bridge › the box carries the palette's chord, inside the box |
| A3-21 | (bridge) | FEAT | The chip opens the palette and does not steal the box's focus | mousedown preventDefault | ✓ | search-bridge › the chip opens the palette, and does not steal the box's focus doing it |
| A3-22 | (bridge) | FEAT | The input reserves room for the chip, so a long query never runs under it | `.search input` padding-right | ✓ | search-bridge › the chip leaves room for itself |
| A3-23 | (bridge) | FEAT | A live n/total count while the box has a query; nothing when it is empty | `#s-cnt`, `.has-cnt` | ✓ | search-bridge › the graph count is what the filter kept · clearing the box takes the count away again · an empty box counts nothing |
| A3-24 | (bridge) | FEAT | Each view counts its own: the graph live off Cytoscape, catalog and files from inside their render | `bridgeSync`/`bridgeReport` | ✓ | search-bridge › the catalog and the files tree count their own rows · a view with no search box has no count either |
| A3-25 | (bridge) | FEAT | Zero local matches raises a panel naming the bundle and the query, instead of a silently empty view | `#s-bridge`, `.sb-msg` | ✓ | search-bridge › zero matches says so, naming the bundle and the query · a match hides the panel again |
| A3-26 | (bridge) | FEAT | Clear and esc empty the box, restore the view, and return the cursor | `#sb-clear`, clearBox | ✓ | search-bridge › Clear empties the box, restores the view, and returns the cursor · esc in the box is the same as Clear |
| A3-27 | (bridge) | FEAT | The handoff: Enter or the primary action opens the palette prefilled and already searching; the offer returns if the palette closes on a still-dead query | `openPalette(prefill)` | ✓ | search-bridge › a dead-end query hands itself to the palette · Enter in the box is the same handoff · closing the palette on a still-dead query brings the offer back |
| A3-28 | (bridge) | FEAT | No global-search action where there is no hub to answer one | `SEARCH_ENDPOINT`, `#sb-go[hidden]` | ✓ | search-bridge › a standalone bundle offers no global search, because it has none |
| A3-29 | (bridge) | REG | The echoed query is escaped — the panel is a new user-text path into innerHTML | `esc()` in `.sb-msg` | ✓ | search-bridge › a query of markup is echoed as text, not as markup |

## Area 4 — Inspector, links, escaping/sanitization

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A4-01 | d942471 | FEAT | Clicking a node opens the panel and fills type/title/tags | `#side`, showFn | ✓ | inspector › clicking a node opens the panel |
| A4-02 | 8241cc2 | FEAT | Link rows list both directions with counts, as concept rows | `.rellist`, `.rel h4 .c` | ✓ | inspector › the panel lists both link directions |
| A4-03 | d1b485d | REG | Concept body renders as sanitized markdown, not source | `DOMPurify.sanitize(marked.parse)` | ✓ | inspector › the concept body renders as markdown |
| A4-04 | ed6c0af | REG | A relative body link navigates in-app (not a dead 404) | interceptMdLinks, resolveConcept | ✓ | inspector › a body link navigates in place |
| A4-05 | d942471 | FEAT | Close hides the panel; the toggle brings it back | `#btn-panel`, `data-side` | ✓ | inspector › close hides the panel |
| A4-06 | 8241cc2 | REG | Widen goes to 50vw (was 70vw) and back | `data-side=wide` `--side-w:50vw` | ✓ | inspector › widen goes to half the viewport |
| A4-07 | 8241cc2 | FEAT | Panel type/tag chips are clickable filter handles, light when active | `.facet`, `.facet.on` | ✓ | inspector › the type and tag chips drive the graph filter |
| A4-08 | 8ca455f | REG | Escape drops the selection and clears the hash | deselect, replaceState | ✓ | inspector › Escape drops the selection |
| A4-09 | d942471 | FEAT | Selecting a second concept replaces the first | select(id) | ✓ | inspector › selecting a second concept replaces the first |
| A4-10 | ae7a882 | REG | Links to index.md / log.md / bare dir resolve and navigate | resolveTarget, DIRSET | ✓ | links › (all four resolutions) |
| A4-11 | ed6c0af | FEAT | Unresolvable in-bundle links are disabled, not followed | `a.dead` | ✓ | links › an unresolvable link is disabled |
| A4-12 | ae7a882 | REG | Dead-link tooltip reads "not a file in this bundle" | `a.dead[title]` | ✓ | links › an unresolvable link is disabled, not followed (asserts the title) |
| A4-13 | ed6c0af | FEAT | External/absolute links open in a new tab | `window.open(_blank)` | ✓ | links › an external link opens in a new tab and leaves the panel in place |
| A4-14 | d1b485d | REG | Scripts stripped from bodies; prose survives | DOMPurify | ✓ | sanitization › scripts are stripped |
| A4-15 | d1b485d | REG | Event-handler attributes don't survive into the DOM | DOMPurify | ✓ | sanitization › event-handler attributes |
| A4-16 | d1b485d | REG | `javascript:` URLs stripped from links | DOMPurify | ✓ | sanitization › javascript: URLs |
| A4-17 | d1b485d | REG | Same body sanitized in the files reader, not only inspector | renderMarkdown shared | ✓ | sanitization › the same body is sanitized in the files reader |
| A4-18 | ed8a554 | REG | `</script>` in a title can't close the inlined payload | `json_for_script` | ✓ | sanitization › a </script> in a concept title |
| A4-19 | c2cedb6 | REG | A quote in a value can't break out of its HTML attribute | `esc()` escapes `"`/`'` | ✓ | sanitization › a quote in a tag |
| A4-20 | d942471 | FEAT | Title renders as text, markup visible not parsed | esc in markup | ✓ | sanitization › the title renders as text |

## Area 5 — Files view, file tree, reserved files, index-layer list

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A5-01 | 0e9eab8 | REG | A collapsed folder stays collapsed while a search is active | `collapsedDirs`, dropped `!filtering` | ✓ | files-tree › a collapsed folder stays collapsed |
| A5-02 | 4b80b80 | REG | Collapse-all folds inside the root, leaves root+top-level open | `foldable()` excludes `.` | ✓ | files-tree › collapse-all folds every folder inside the root |
| A5-03 | 4b80b80 | REG | Unfold-all clears the whole set incl. a hand-closed root | `collapsedDirs.clear()` | ✓ | files-tree › collapse-all stays reversible |
| A5-04 | adf96ff | FEAT | Collapsing the root folds the list to its header (compact) | `.files-grid.tree-min` | ✓ | files-tree › collapsing the root folds the list |
| A5-05 | 2163bfe | REG | Reopening a root-folded list reopens the root (returns the tree) | `#ftree-min`, `foldedByRoot` | ✓ | files-tree › reopening the list undoes the root collapse |
| A5-06 | 2163bfe | FEAT | A file-folded list reopens without touching root collapse | `foldedByRoot===false` | ✓ | files-tree › (same test, preserves a file collapse) |
| A5-07 | 0e9eab8 | FEAT | Fold/unfold-all control in the Files header | `#ftree-foldall` | ✓ | files-tree › collapse-all |
| A5-08 | 0e9eab8 | FEAT | Fold-all label/aria/disabled/icon reflect folders in view | `syncFoldAll()` | ✓ | files-tree › the fold-all control reflects the folders' collapsed state |
| A5-09 | 4b80b80 | FEAT | File tree nests directories by depth, parent above child | `subtree()`, `--d` padding | ✓ | files-tree-nested › directories nest by depth (computed padding-left grows folder→subfolder→file) |
| A5-10 | 4b80b80 | FEAT | A dir containing only sub-dirs still renders | `dirParents()` | ✓ | files-tree-nested › a directory that holds only a subdirectory still renders |
| A5-11 | 4b80b80 | FEAT | Folder headers show only the last path segment | `dir.split('/').pop()` | ✓ | files-tree-nested › a folder header shows only the last path segment |
| A5-12 | 1093ae3 | REG | Reader header hidden when no file open (`.fp-head[hidden]`) | `.fp-head[hidden]{display:none}` | ✓ | files-tree › the reader header is hidden until a file is open |
| A5-13 | 1093ae3 | FEAT | index/log rows sit at the top of their folder in the tree | `resIn(dir,depth)` order | ✓ | files-tree › index/log rows sit above the concept files in their folder |
| A5-14 | 1093ae3 | FEAT | "Indexes only" toggle narrows the tree to the authored layer | `#ftree-ixonly`, `ixOnly` | ✓ | indexes › the indexes-only toggle narrows the tree to the authored maps |
| A5-15 | c7bb1b5 | REG | Opening a concept releases the Indexes-only filter | openFile→`setIxOnly(false)` | ✓ | indexes › opening a concept releases the filter |
| A5-16 | c7bb1b5 | REG | Opening a map does NOT release the Indexes-only filter | openReserved (no setIxOnly) | ✓ | indexes › opening a map does not release |
| A5-17 | 646f3f5 | REG | "Open in graph" on a map jumps to its folder / draws that map | openMapInGraph, centerOn | ✓ | indexes › a map offers the graph button and it lands |
| A5-18 | c7bb1b5/815d5c1 | REG | A log hides its "Open in graph" button (`[hidden]` honoured) | `.btn.text[hidden]{display:none}` | ✓ | indexes › a log hides the graph button |
| A5-19 | 3376b9a | REG | Every file's graph button reads one static "Open in graph" | `#fp-graph .fpg-lbl` text | ✓ | indexes › every file's graph button reads one static "Open in graph" |
| A5-20 | 1093ae3 | FEAT | Type/tag combos hide reserved files while set | `res` populated only if `!ft&&!fg` | ✓ | files-tree › setting a combo filter hides the reserved index/log rows |
| A5-21 | ee4788a | REG | ixOnly renders reserved as a flat list at folder depth (no headers) | `.file[data-res]` `--d`, flatRes | ✓ | indexes › indexes-only renders the reserved files flat, with no folder headers |
| A5-22 | ee4788a | FEAT | ixOnly row shows full path; full tree shows bare filename | `.rn` text vs `data-path` | ✓ | indexes › an indexes-only row carries the full path; the full tree shows the bare name |
| A5-23 | ee4788a | REG | ixOnly fold-all reflects nothing to fold | `#ftree-foldall` disabled | ✓ | indexes › the fold-all control is disabled in indexes-only |
| A5-24 | ee4788a | FEAT | ixOnly with no matches shows an empty-state message | `.empty` text | ✓ | files-tree-nested › indexes-only shows the empty state when there are no index or log files (tree fixture has no reserved files) |
| A5-25 | 8241cc2 | REG | A long tree-row path ellipsizes, doesn't push its badge off-edge | `.rn{min-width:0;overflow:hidden}` | ✓ | files-tree-deeppath › a long indexes-only row ellipsizes instead of pushing its badge off the edge (fixtures/deeppath, 39-char map path) |
| A5-26 | d942471/dc83857 | FEAT | Files type & tag comboboxes (keyboard-navigable) filter the tree | `#file-type-combo`, `#file-tag-combo` (role) | ✓ | files-tree › picking a type narrows the tree; clearing restores it (type combo + ✕; tag combo + keyboard nav not separately asserted) |
| A5-27 | 05b2bbb | FEAT | Reserved files re-fetch fresh on open (a new log entry shows) | `LOGS=null` before getLogs | ✓ | files-tree › a log re-reads on every open, so a new entry shows (route flips the flag; server-only) |
| A5-28 | 05b2bbb | FEAT | Folder sections fold/unfold; state ignored while filtering | `.ffolder.closed`, filtering guard | ✓ | files-tree › a collapsed folder stays collapsed |

## Area 6 — Mobile / responsive, touch preview

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A6-01 | adf96ff | FEAT | ≤768px: rail becomes an off-screen drawer, ☰ opens it, backdrop closes | `#app.nav-open`, `#btn-menu`, `#nav-bk` | ✓ | responsive › the rail becomes a fixed drawer (+ hamburger/backdrop) |
| A6-02 | adf96ff | FEAT | ≤768px: topbar tools fold into a ⚙ sheet | `#btn-controls`, `#app.controls-open` | ✓ | responsive › the controls toggle folds the tools row |
| A6-03 | adf96ff | FEAT | Opening Filters folds the sheet away | ctlSet(false) | ✓ | responsive › opening Filters folds the sheet |
| A6-04 | adf96ff | FEAT | Nothing overflows the viewport horizontally | body scrollWidth | ✓ | responsive › nothing overflows |
| A6-05 | adf96ff | FEAT | ⚙ controls toggle is absent on the Stats view | `#app[data-view=stats] #btn-controls` | ✓ | responsive › the controls toggle is gone on Stats |
| A6-06 | adf96ff | FEAT | ⚙ carries a filter-count badge mirroring the active filters | `ctlBadge()`, `.fbadge` | ✓ | responsive › the ⚙ toggle carries the active-filter count even with the sheet folded away |
| A6-07 | dec7cad | REG | Folded tools sheet is two even columns, no orphaned icon | flex-basis calc(50%-4px) | ✓ | mobile-layout › the folded tools sheet is two even columns |
| A6-08 | a5f12ab | REG | Mobile layout `<select>` fills its wrapper (chevron clickable) | `#layout` width:100% | ✓ | mobile-layout › the layout select fills its wrapper |
| A6-09 | a5f12ab | FEAT | Mobile icon-button row groups (no space-between) | `#graph-controls` gap only | ✓ | responsive › the folded tools sheet groups the icon row |
| A6-10 | b376e8c | REG | Tree header lays out identically at every width (one line) | `.ftabs`, margin-auto placement | ✓ | mobile-layout › the file-tree header stays on one line |
| A6-11 | b376e8c | REG | Pane-toggle flush with neighbours at every width | `#ftree-min` no margin-bottom | ✓ | mobile-layout › the file-tree header stays on one line — `#ftree-min` is mobile-only (`display:none` on desktop), so "every width" is every width it renders; the shared-centre check reads all visible `.ftabs > *` incl. the toggle, and was mutation-verified to go red on a `margin-bottom:10px` offset |
| A6-12 | ??/mobile | REG | The ident ellipsizes instead of overflowing the bar | `.ident` ellipsis | ✓ | mobile-layout › the ident ellipsizes |
| A6-13 | f00cb66 | REG | Persisted splitter width clamped to 70% of viewport on restore | `Math.min(w,innerWidth*.7)` | ✓ | splitters › a stored width wider than the viewport is clamped |
| A6-14 | adf96ff | FEAT | ≤768px collapsing root also folds the stacked list to header | `treeMin(true)` | ✓ | files-tree (mobile reopen path) |
| A6-15 | (preview) | REG | A touch-width node tap no longer opens `#side` — `#stage` keeps its full width instead of measuring 0 | `openPanel()` refusal | ✓ | mobile-preview › a tap fills the card and the graph keeps every pixel it had |
| A6-16 | (preview) | FEAT | The card carries the concept's head: type chip, title, lazy description, `N links out · N in` | `#pv-head-in` | ✓ | mobile-preview › a tap fills the card… (title + `.pv-meta`) |
| A6-17 | (preview) | FEAT | The camera aims at the middle of the visible band, not the canvas centre, so the selection is never under the card | `panToBand` | ✓ | mobile-preview › the selected node is above the card |
| A6-18 | (preview) | REG | Dot → dot swaps the card's contents in place; one element, reused | `fill()` without `raise()` | ✓ | mobile-preview › dot to dot swaps the card in place |
| A6-19 | (preview) | REG | A miss on bare canvas does **not** dismiss the card (the misses are constant at this size, and each dismissal replayed the entrance) | no `close()` on canvas tap | ✓ | mobile-preview › a miss on bare canvas leaves the card up |
| A6-20 | (preview) | REG | Nothing animates: the card takes exactly one transform value for its whole life on screen, across open / swap / close / reopen | no `transition:transform` | ✓ | mobile-preview › the card wears exactly one transform for its whole life on screen |
| A6-21 | (preview) | FEAT | Three snap points (peek / half / full); at full the card's own body scrolls and the drag surface does not extend over it | `snapH`, `touch-action` | ✓ | mobile-preview › at full the card's own body scrolls and the card stays put |
| A6-22 | (preview) | FEAT | A neighbourhood row walks to that concept in place — the card never closes, and the snap point is kept | `[data-go]` → `select` | ✓ | mobile-preview › a Links to row walks to that concept without closing the card |
| A6-23 | (preview) | FEAT | Dismissal is explicit: ✕, Esc, or a downward drag past 55% of peek | `close()`, `upEv` | ✓ | mobile-preview › ✕ and Esc both dismiss it · a downward drag on the grip throws it away |
| A6-24 | (preview) | FEAT | The grip is a slider: ↑/↓ resize, ↓ at peek closes, Enter/Space toggles | `#pv-grip[role=slider]` | ✓ | mobile-preview › at full the card's own body scrolls (↑↑ to full) |
| A6-25 | (preview) | FEAT | A short, still press on the head toggles peek ↔ half | `d.moved<8` | ✓ | mobile-preview › tapping the head toggles peek and half |
| A6-26 | (preview) | REG | Folder, area and index taps fill the card too — they used to write into an invisible `#side-body` and do nothing visible at all | `fillDir`/`fillLog` | ✓ | mobile-preview › a folder tap fills the card too |
| A6-27 | (preview) | FEAT | The canvas hint stands down under the card rather than sitting behind it | `#app.preview-up .ghint` | ✓ | mobile-preview › the canvas hint stands down under the card |
| A6-28 | (preview) | FEAT | The branch is ≤768px **or** ≤1024px portrait, so a portrait tablet runs the card and a landscape window of the same size keeps the inspector | `MOBILE_MQ` | ✓ | mobile-preview › the card runs here too (820×1180) · the desktop is untouched (1600×1000) |
| A6-29 | (preview) | FEAT | On a portrait tablet the card insets past the 76px rail, which is still on screen there | `#preview{left:76px}` | ✓ | mobile-preview › the card runs here too, but starts where the rail ends |
| A6-30 | (preview) | REG | On the card branch `#btn-panel` is hidden and `\` is inert — the inspector they toggled could only ever show its placeholder | `setSide()` pinned to hidden | ✓ | mobile-preview › the inspector toggle is gone, rather than opening an empty panel |
| A6-31 | (preview) | FEAT | Off the branch the card is `display:none`: no layout, no widened document | `#preview.up` only in the MQ | ✓ | mobile-preview › a click still opens the side inspector and the card never appears |
| A6-32 | (preview) | FEAT | The card is a second render path over the same authored strings, and holds both defenses: heads through `esc()`, bodies through `renderMarkdown` | `fill()`, `loadBody()` | ✓ | mobile-preview › a title of markup is shown as text, and the body is sanitized (fixtures/hostile, phone width) |
| A6-33 | (preview) | FEAT | No horizontal overflow with the card up, at 375 / 820 / 1600 | `documentElement.scrollWidth` | ✓ | mobile-preview › nothing the card does makes the page scroll sideways · no sideways scroll at tablet width either |

## Area 7 — First-visit notes

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A7-01 | cc7d545 | FEAT | A dismissible `#hello` welcome note rides the graph, "Read the index" | `#hello`, `#hello-go` | ✓ | first-visit › the welcome note shows |
| A7-02 | 3ce2284 | REG | "Read the index" opens root index.md in the reader (not the list) | `#hello-go`→readIndex | ✓ | first-visit › Read the index dismisses and opens the index |
| A7-03 | cc7d545 | FEAT | Dismissal remembered across visits | localStorage `okf-hello` | ✓ | first-visit › dismissing stays dismissed across a reload |
| A7-04 | 3ce2284 | FEAT | Canvas hint (`.ghint`) stands down while the note is up, restored on dismiss | `gh.style.visibility` | ✓ | first-visit › the canvas hint stands down / restores the hint |
| A7-05 | 3ce2284 | FEAT | A second `#hello2` note points at ☰ on leaving the graph (compact) | `#hello2`, setView hook | ✓ | first-visit › a second note points at the other views |
| A7-06 | cc7d545 | FEAT | The note belongs to the graph, disappears on other views | `#app:not([data-view=graph]) ~ #hello` | ✓ | first-visit › the welcome note belongs to the graph and hides on other views |
| A7-07 | 3ce2284 | FEAT | ☰ dismisses `#hello2` (only once on screen), remembered | hello2Done early-return | ✓ | first-visit › opening ☰ answers the second note and remembers it |
| A7-08 | cc7d545/3ce2284 | FEAT | Note wording follows pointer type & width (tap/pinch, ☰ mention) | `@media (pointer:coarse)`/width | ✓ | first-visit › a touch primary pointer swaps the note's click wording for tap/pinch (`isMobile`+`hasTouch`) |
| A7-09 | 3ce2284 | FEAT | `#hello` reflows for short & landscape-phone viewports | `@media (max-height:480px)` | ✓ | first-visit › the welcome note reflows to a two-column grid when the viewport is short (900×450) |
| A7-10 | adf96ff | FEAT | A "best on desktop" `#mnote` shows on small screens, dismiss/persist | `#mnote`, `okf-mnote` | ⊘ | **superseded** — cc7d545 deleted `#mnote`/`okf-mnote` and folded the mobile note into `#hello2` (A7-05/A7-07), pinned by a `refute_includes` render test. Not a gap; the feature is gone. |

## Area 8 — Command palette, hub, help, keyboard sheet

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A8-01 | adf96ff/8241cc2 | FEAT | ⌘K palette opens focused, Esc/⌘K close, modal | `#sw`, keydown | ✓ | palette › Ctrl-K opens it focused |
| A8-02 | 8241cc2 | FEAT | Typing a view + Enter jumps to it (view row switches in place) | `a[data-view]`, go() | ✓ | palette › typing a view and pressing Enter |
| A8-03 | 01d39a5 | REG | The Index palette row lands on Files, never a blank view | go()→goRail | ✓ | palette › the Index row lands on Files |
| A8-04 | adf96ff | FEAT | Arrow keys move the active option (aria-activedescendant) | `.active`, ↑↓ | ✓ | palette › the arrow keys move the active option |
| A8-05 | adf96ff | FEAT | Hub palette lists the sibling bundle, current row on top | `#sw-list a[data-path]`, `.cur` | ✓ | palette-hub › opens in bundle-switch mode |
| A8-06 | adf96ff | FEAT | Discovery badge shows bundle count, retires after first open | `#sw-count`, `okf-swseen` | ✓ | palette-hub › the discovery badge |
| A8-07 | adf96ff | FEAT | Choosing the sibling navigates to it | go()→location | ✓ | palette-hub › choosing the sibling navigates |
| A8-08 | 8241cc2 | FEAT | ⌘⏎ opens a bundle row in a new tab; view rows ignore the chord | window.open(_blank) | ✓ | palette-hub › the ⌘⏎ chord |
| A8-09 | adf96ff | FEAT | ⇄ Switch rail button shown only in hub mode | `#btn-switch[hidden]` | ✓ | palette › the ⇄ switch-bundle button is hidden in standalone + palette-hub › shown in hub mode |
| A8-10 | adf96ff | FEAT | Palette empty states: "no matches" vs only-this-bundle | `a.none` | ✓ | palette › a query matching nothing shows the no-matches note (standalone has no /search, so FINDS is false and a no-view query falls through; "only this bundle" needs a one-bundle registry hub, still open) |
| A8-11 | adf96ff | FEAT | Sibling links carry current view+layout as query params | `target()` | ✓ | palette-hub › a sibling link carries the current view and layout, dropping the selection |
| A8-12 | 8241cc2 | REG | Palette first row is visible on open (unhide before render/scroll) | open() ordering | ✗ | uncovered |
| A8-13 | 01d39a5 | FEAT | `?`/help button opens a modal shortcut sheet listing bindings | `#kb`, `#btn-help` | ✓ | help › ? opens the sheet and lists the bindings |
| A8-14 | 01d39a5 | FEAT | Esc closes the sheet; a second `?` toggles it | kbClose | ✓ | help › Esc closes it |
| A8-15 | (suite) | FEAT | Help sheet manages focus: close on open, opener on close | focus mgmt | ✓ | help › the sheet manages focus |
| A8-16 | (unbuilt) | — | Help sheet focus *trap* (Tab cycling within modal) | — | ✗ | **feature does not exist** (Tier 3) |
| A8-17 | (panel) | FEAT | ⚙ in the rail opens a Bundles slide-over, subtitled with the count | `#btn-ws`, `#ws`, `#ws-sub` | ✓ | bundles-panel › the ⚙ in the rail opens a slide-over that says what it is and how much |
| A8-18 | (panel) | FEAT | A row carries the title (linked), @slug, concept count and health **word** | `.ws-row`, `.ws-health` | ✓ | bundles-panel › a row carries every fact a reader chooses between bundles by |
| A8-19 | (panel) | FEAT | The default and the bundle being read are each marked, and differently | `.ws-pill.def`, `.ws-pill.cur` | ✓ | bundles-panel › the default and the one being read are each marked, and differently |
| A8-20 | (panel) | FEAT | Behind a hub the wordmark is a link back to the bundle list | `a.rail-brand` | ✓ | bundles-panel › the wordmark is the way back to every bundle |
| A8-21 | (panel) | REG | A closed slide-over takes no layout — `hidden`, not merely translated | `#ws[hidden]` | ✓ | bundles-panel › a closed panel takes no layout · closed means display:none, not merely off-canvas |
| A8-22 | (panel) | REG | Nor does one mid-slide: `#views` clips, as `#stage` always did for Filters | `#views{overflow:hidden}` | ✓ | bundles-panel › nor does one mid-slide, which is where it actually showed (scrollWidth sampled across the whole animation) |
| A8-23 | (panel) | FEAT | One ⋯ per row; Make default / Rename… / Remove…, the last in red | `.ws-menu-btn`, `.ws-menu` | ✓ | bundles-panel › each row carries one ⋯, and the verbs live in its menu |
| A8-24 | (panel) | FEAT | Make default is disabled on the row that already is, and says so | `button[data-act=default][disabled]` | ✓ | bundles-panel › the default row's Make default is disabled, and says why |
| A8-25 | (panel) | REG | esc peels one layer — the menu first, then the panel — never nothing | keydown guard on `menuFor` | ✓ | bundles-panel › esc peels one layer: the menu first, then the panel · two menus are never open at once |
| A8-26 | (panel) | FEAT | Rename takes over the row with a field and a hint; Cancel restores it | `.ws-edit`, `.ws-hint` | ✓ | bundles-panel › Rename takes over the row, and Cancel puts it back untouched |
| A8-27 | (panel) | FEAT | Save renames and the list re-reads from the server, mount and all | POST registry/rename | ✓ | bundles-panel › Rename saves, and the whole list comes back knowing the new name |
| A8-28 | (panel) | FEAT | Make default moves the badge, and `/` agrees on the next request | POST registry/default | ✓ | bundles-panel › Make default moves the badge, and the server agrees |
| A8-29 | (panel) | FEAT | Remove confirms in the row, naming what does *not* happen to the folder | `.ws-confirm` | ✓ | bundles-panel › Remove states what it will and will not do · Remove removes, and the bundle stops being served |
| A8-30 | (panel) | REG | An empty list says so and names the way out, rather than rendering nothing | `.ws-empty` | ✓ | bundles-panel › with nothing left, the panel says so and names the way out |
| A8-31 | (panel) | FEAT | Read-only keeps every fact, drops every control, and explains which and how | `.ws-ro-note`, `MANAGE_TOKEN` null | ✓ | bundles-panel › read-only › every fact stays, and every control goes · and a sentence says why, and how · the page holds no token it may not use |
| A8-32 | (panel) | FEAT | No registry behind the page means no ⚙ at all, and no token in it | `MANAGE_ROOT` null | ✓ | bundles-panel › no registry behind the page means no ⚙ at all |
| A8-33 | (panel) | FEAT | No Add — registering is the agent's act, and the footer says where | `.ws-foot` | ✓ | bundles-panel › the footer says who adds a bundle, because the panel does not |

## Area 9 — Deep links, theme, splitters, diagram, static/server, interiors

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A9-01 | a6da350/d942471 | FEAT | `?view=` opens that view on arrival | Q.get('view')→setView | ✓ | deep-links › ?view= opens that view |
| A9-02 | 1093ae3 | REG | `?view=index` opens root index.md (place no longer exists) | QV==='index'→readIndex | ✓ | deep-links › ?view=index resolves to Files |
| A9-03 | d942471 | FEAT | `?layout=` selects and applies that layout | Q.get('layout') | ✓ | deep-links › ?layout= |
| A9-04 | d942471 | FEAT | `?select=` selects the node and shows it | QS→goToGraph | ✓ | deep-links › ?select= |
| A9-05 | d942471 | FEAT | A `#hash` selects that node; reacts to hashchange | fromHash | ✓ | deep-links › a #hash selects that node |
| A9-06 | 4b80b80 | FEAT | `?select=`/`#hash` carry the graph view with them | goToGraph | ✓ | deep-links › a selection carries the view |
| A9-07 | d942471 | FEAT | Theme toggle flips light/dark and persists | `#btn-theme`, `okf-theme` | ✓ | theme › the toggle flips both ways |
| A9-08 | d942471 | FEAT | Theme resolved before first paint (no flash), survives reload | `<head>` boot script | ✓ | theme › the choice survives a reload |
| A9-09 | d942471 | FEAT | Boot follows `prefers-color-scheme` when nothing stored | matchMedia in boot | ✓ | theme › boots dark / boots light |
| A9-10 | d942471 | FEAT | Toggling theme re-themes Cytoscape and re-renders Mermaid | applyCyTheme, rethemeMermaid | ✓ | diagram › toggling the theme re-renders the inline diagram |
| A9-11 | ed6c0af | FEAT | Inspector splitter: drag widens, persists, dbl-click resets | `#side-resizer`, `okf-side-w` | ✓ | splitters › (restore/reset/drag/persist) |
| A9-12 | ed6c0af | FEAT | Files column splitter: drag widens, persists | `#ftree-resizer`, `okf-ftree-w` | ✓ | splitters › dragging the handle widens the tree column |
| A9-13 | 357ae87 | FEAT | A Mermaid block opens a fullscreen viewer (click/tap/Enter/Space), focused | `.mermaid[role=button]`, `#dgv` | ✓ | diagram › clicking a rendered diagram opens the viewer |
| A9-14 | 357ae87 | FEAT | Escape closes the viewer, returns focus to the diagram | closeDiagram | ✓ | diagram › Escape closes the viewer |
| A9-15 | 357ae87 | FEAT | Viewer re-renders from source (keeps colors), not a clone | `m.dataset.src` | ✓ | diagram › (re-rendered from source) |
| A9-16 | 357ae87 | FEAT | Viewer pan (drag), zoom (wheel/pinch/±), reset (btn/dbl-click) | `#dgv-in/out/reset`, panzoom | ✓ | diagram › the viewer's zoom controls scale the diagram, and reset returns it (±/reset buttons; drag-pan + wheel/pinch not asserted) |
| A9-17 | 357ae87 | FEAT | While the viewer is open, other shortcuts are suppressed | keydown early-return | ✓ | diagram › the open viewer swallows the page's other shortcuts |
| A9-18 | 357ae87 | FEAT | Mermaid blocks: zoom-in cursor, accent hover, focus outline | `.mermaid` CSS | ✓ | diagram › a rendered diagram block advertises that it opens — zoom-in cursor, accent hover (`:focus-visible` outline is keyboard-only, left to the eye) |
| A9-19 | ed8a554 | FEAT | `EMBED` switches all five data reads: baked (static) vs fetched (server) | EMBED const | ✓ | proven by the two-project harness (every spec ×2) |
| A9-20 | ed8a554 | FEAT | Server getters hit endpoints (bodies never memoized → live edits) | fetch NODE/META | ✓ | inspector › server mode never memoizes a body — re-opening re-fetches it fresh (route flips the marker; server-only) |
| A9-21 | d942471 | FEAT | Catalog cards: type chips, "X of Y" count, click → graph | `.card`, `#cat-cnt` | ✓ | interiors › a card opens that concept; views |
| A9-22 | d942471 | FEAT | Catalog type chip narrows the grid and its count | `.card` filter | ✓ | interiors › a type chip narrows the grid |
| A9-23 | d942471 | FEAT | Tags cloud: select lists concepts, second tag adds, click → graph | `.tcloud`, `#tag-detail` | ✓ | interiors › selecting a tag / a second tag adds |
| A9-24 | d942471 | FEAT | Stats count-up animation on the stat cards | `.stat` countUp | ✓ | interiors › a stat card counts up to its value rather than snapping (catch a >8 stat mid-climb via waitForFunction — the 600ms window is reliably caught, not a timed race) |
| A9-25 | boot | FEAT | Third-party libs (Cytoscape/marked/DOMPurify) present at boot | globals | ✓ | boot › the third-party libraries are present |
| A9-26 | boot | FEAT | Header counts match the bundle; type legend chips+counts; (root) chip | `#cat-cnt`, legend | ✓ | boot › the header counts / type legend / (root) chip |

---

## Bugs this suite found

Building this coverage turned up three real, shipped bugs no string assertion
could see. All three are now fixed and pinned (they are the ✓ rows A5-18, A2-05,
A2-34):

1. **The graph collapsed on return, and the cause was misdiagnosed for months.**
   Dwell on another view, come back, and the graph redrew at a tenth of its size.
   The held-open note blamed a resize race; tracing the one zoom animation that
   actually ran showed it was a **fit**. `fitGraph` computes the zoom from the
   container's own width, and the boot fit (`setTimeout(fitGraph, 400)` after
   load) fires on whatever view is up by then — leave the graph inside that
   window and it fits a hidden 0×0 canvas, `(w-2*pad)/bb.w` goes negative, and the
   zoom clamps to minZoom, staying there on return. Fixed by guarding `fitGraph`
   to skip a zero-size canvas. The lesson: the old repro's load-sensitivity was
   the *symptom* (a timer racing boot), not noise to route around with a `fixme`.

2. **A log's "Open in graph" button stayed visible though the code hides it** —
   `.btn.text{display:inline-flex}` outranked `.btn[hidden]{display:none}` at
   equal specificity, so a `hidden` button still rendered ~143px wide with a
   stale handler. Fixed with `.btn.text[hidden]{display:none}`. **The sibling of
   this bug class, the reader header (`.fp-head[hidden]`, A5-12), is now covered
   too** — files-tree › "the reader header is hidden until a file is open",
   mutation-checked by dropping the `.fp-head[hidden]` rule.

3. **Selection was illegible in cluster mode** — `focusNode` dimmed the compound
   area boxes, whose opacity cascades to the nodes inside them, so the whole graph
   faded. Fixed to dim leaves and edges, never `:parent`.

One camera fix (one-camera-move-per-click, A2-33) is covered too, but only via a
test-only page counter (`window.__camCenters`) — see the note in the worklist's
Priority-4 rationale: it had no external observable, so the page was made
observable. That is the exception, not the pattern.

## Superseded (⊘) — excluded from the denominator

Reverted or replaced later; do NOT write tests for these:

- **Landing-page work (4b80b80)** — boot on Files w/ index open, boot search
  placeholder, first-reveal refit → all reverted by **cc7d545** (boot on graph).
- **Standalone Index & Log views (a6da350)** → Log folded into Files (05b2bbb),
  Index → Files|Indexes tabs (4f4aae4) → tabs dissolved into one tree (1093ae3).
  The "Index rail item lands on Files" survives (A1-05); the panels/tabs/ARIA-tab
  state do not.
- **Number-key mappings** — remapped 5× (d942471→05b2bbb→4f4aae4→a2f6db1→1093ae3).
  Only the **final** mapping (A1-04) is live.
- **Flat "Indexes & log" tree section (ae7a882)** → replaced by tabs (4f4aae4) →
  replaced by inline reserved rows (1093ae3).
- **Index-layer node color** — accent (aeef15b) → grey like folders (f73ed5f) →
  accent again (456aa79) → folders also accent (1498a7c). Only the **final**
  unified look (A2-19, A2-22) is live.
- **open-map-no-dim (d0b4fed)** — "opening a map dims nothing" → reverted by
  9158ca6 (full neighbourhood emphasis, A2-10).
- **Per-file graph-button labels (cc7d545)** — "Explore the knowledge graph" /
  "Open X/ in graph" → collapsed to one static "Open in graph" (3376b9a, A5-19).
- **Inspector 70vw wide preset (d942471)** → 50vw (8241cc2, A4-06).
- **The "best on desktop" `#mnote` (adf96ff)** → deleted by cc7d545, which folded
  the mobile note into `#hello2` and took `okf-mnote` with it (a `refute_includes`
  render test pins the removal). This is **A7-10**, kept as a rowed ⊘ above
  because it read as a live gap in earlier passes until the history was walked.

---

## Uncovered worklist — what is still missing

Ranked by value × cheapness. **Tier-cheap** = writeable against existing or one
small new fixture, deterministic, no product change. **Needs-fixture** = add a
bundle/dir first. **Needs-instrumentation/hard** = no external handle, or a
product change, or genuinely untestable headless.

### Priority 1 — REG fixes, cheap, existing fixtures — ✅ CLEARED

All ten were written and mutation-checked (break the handle, confirm red for the
predicted reason, restore); A4-12 was found already covered and corrected. The
covering specs are in the row tables above. Kept here as the closed record:

| ID | Behavior | Covering spec |
|---|---|---|
| A5-12 | Reader header hidden when no file open | files-tree › the reader header is hidden until a file is open |
| A2-08 | Tapping a folder node emphasises it | emphasis › tapping a folder node in tree mode |
| A2-09 | Tapping a map node emphasises it | emphasis › tapping a map node in the index layer |
| A2-13 | Cluster disables the layout selector | graph-modes › cluster disables the layout selector (cluster/tree are mutually exclusive; cluster disables `#layout` only — it does **not** disable `#btn-tree`, correcting the original note) |
| A2-27 | Entering tree disables `#btn-ix`, tears down layer | graph-modes › entering tree mode disables the index button and tears down the layer |
| A4-12 | Dead-link tooltip text | links › an unresolvable link is disabled (already asserted the `title`; stale ✗ corrected) |
| A4-13 | External links open in a new tab | links › an external link opens in a new tab (added an external link to rollback.md in a `# Citations` section, kept validate+lint clean) |
| A6-05 | ⚙ controls toggle absent on Stats | responsive › the controls toggle is gone on Stats |
| A6-09 | Mobile icon-button row grouping | responsive › the folded tools sheet groups the icon row |
| A5-19 | One static "Open in graph" label | indexes › every file's graph button reads one static "Open in graph" |
| A7-07 | ☰ dismisses `#hello2` once on screen | first-visit › opening ☰ answers the second note and remembers it |

### Priority 2 — FEAT, cheap, existing fixtures

**Done so far** (see the row tables): A1-08 (`0` fits), A1-09 (`\` inspector),
A2-19/A2-20 (tree accent nodes + dashed edges), A5-08 (fold-all states), A5-13
(reserved-row ordering), A5-14 (indexes-only narrowing), A7-06 (note scope),
A9-17 (viewer swallows shortcuts), A9-16 (viewer zoom/reset controls), A2-18
(folder nodes unselectable + filter-exempt), A6-06 (⚙ filter badge), A3-18
(catalog area/tag filter + find box), A3-19 (tags Types/Areas filter + recount),
A5-26 (Files type/tag comboboxes narrow the tree). Remaining:

| ID | Behavior | Handle |
|---|---|---|
| A8-12 | Palette first row visible on open | scroll position after open — trivially true with the 6 view rows that fit; needs an initial list taller than the 46vh max to stress (a 20+ bundle registry hub), and the active row starts at index 0 so even then it sits at the top |

> **Two of the four palette rows (A8-09, A8-11) are now closed** — the standalone
> switch-button-hidden and the sibling link carrying view+layout, both added
> straight onto `palette.spec.js` / `palette-hub.spec.js` (the earlier "wait for
> the server-UI work" note was over-cautious: the palette code is committed and
> stable, so these were writable now). The two that remain are not blocked either,
> just awkward to *stage* — see the reasons above.

### Priority 3 — needs a new fixture

| ID | Behavior | Fixture to add |
|---|---|---|
| A5-10, A5-11, A5-09 | Dir with only sub-dirs, last-segment headers, depth nesting | **done** — `fixtures/tree` (nested dirs, own server + static page). The pattern to copy for the rest of this tier. |
| A3-07 | Tag chips capped at 40 | **done** — `fixtures/manytags` (45 tags, own server + static page) |
| A5-21/22/24 | ixOnly flat list / full-path label / empty-state | **done** — A5-21/22 reached the main fixture's own reserved files (they never needed a fixture); A5-24's empty state uses `fixtures/tree`, which has no maps |
| A9-20 | Server live-edit reflection | **done** — no file mutation needed; `route` serves gateway's body from a flag the test flips, re-open shows the new text (server project only, static skipped) |
| A3-15 | Prefix/fuzzy search | **done** — needed no fixture; a one-edit typo on the main bundle's gateway, polled past the lazy index build |
| A2-36 | Zoom floor auto-relaxes (`relaxZoom`) | **done** — `fixtures/biggraph`, a 100-node ring that cose lays out ~3.5× the canvas height, drives `minZoom` to ~0.17 < the 0.2 default (own server + static page) |
| A5-25 | Long tree-row path ellipsizes | **done** — `fixtures/deeppath` buries a concept five dirs down so its authored index.md's path (39 chars) genuinely overflows the `.rn` box; the spec reads the clip (scrollWidth>clientWidth + computed overflow:hidden/ellipsis), mutation-checked by dropping overflow:hidden |

### Priority 4 — hard / needs instrumentation / genuinely untestable headless

| ID | Behavior | Why hard |
|---|---|---|
| A1-10 | `f` fullscreen | **done** — real fullscreen is unreliable headless, but the page's contract is that `f` *calls* `requestFullscreen` on `#app`; a test-side spy on the API captures exactly that |
| A1-11 | Reduced-motion | **done** — `app.emulateMedia({reducedMotion})` flips it live and the transition strip is a clean computed-CSS read; the count-up half stays visual (A9-24) |
| A2-29 | Stale `/index` fetch dropped (ixSeq) | **done** — `route` holds `/index` ~400ms; toggle on-then-off, and the late response draws nothing (server project only) |
| A2-30 | Layout cose-fallback on CDN failure | **done** — `app.route(/fcose|cose-base|layout-base/).abort()` then select fcose; the selector lands on cose |
| A2-37 | Node spacing across layouts | pure visual, no clean handle |
| A2-26 | Index nodes absent from catalog/tags/types | an absence-proof with no mutation handle — index nodes are simply never added to `NODES`/`CATALOG`, so there is no line to break to make a map appear as a concept; a passing assertion would certify nothing |
| A3-16 / A3-17 | Substring fallback + lazy index build | **done** — not a timing race after all: the MiniSearch *CDN script* is `route`-interceptable. A3-17 flags the request (absent at boot, present on first search focus); A3-16 aborts it and a title substring still narrows via the fallback |
| A5-27 | Reserved re-fetched fresh | **done** — `route` on `/log` serves the log from a flip flag; re-opening shows the new entry (server project only) |
| A9-24 | Stats count-up animation | **done** — the 650ms climb is a wide window; `waitForFunction` catches a >8 stat strictly between 0 and its target, deterministically |
| A7-08/09 | Note gesture wording / short-viewport reflow | **done** — not visual after all: `isMobile`+`hasTouch` emulates `pointer:coarse` (tap/pinch wording) and a 900×450 viewport triggers the `max-height:480px` grid reflow, both clean computed-CSS reads |
| A9-18 | Mermaid block cursor / accent hover / focus outline | **done** — cursor:zoom-in is an always-on computed read, and `.hover()` turns the border accent; both mutation-checked. Only the keyboard-only `:focus-visible` outline is left to the eye |
| A8-16 | Help focus *trap* | **feature unbuilt (Tier 3)** — build it, then test |

---

## How to drive this to full coverage

**Where it stands: 176/181 (97%), 1 partial, 4 uncovered.** Priority 1 is
cleared, every Priority-2 row outside the command palette is ✓, and Priority 3 is
done — on the strength of four new fixtures (`fixtures/tree` nested dirs,
`fixtures/manytags` 45 tags, `fixtures/deeppath` a five-deep reserved path,
`fixtures/biggraph` a 100-node ring), each served on its own port and baked to its
own static page like `fixtures/hostile`, so none disturbs the flat 8-concept
fixture's count assertions. A whole tier once filed as "hard" fell to emulation,
route interception and the fixture pattern with no heroics: reduced-motion, fuzzy
search, the cose fallback, the tap/pinch pointer wording and short-viewport
reflow, the diagram cursor + hover, the server's non-memoized re-fetch and
stale-`/index` drop, the zoom floor (a 100-node ring), fullscreen (an API spy),
the count-up (a `waitForFunction` across the 600 ms climb), orientation (a
dispatched event), the lazy index build and its substring fallback (`route` on
the MiniSearch CDN), and the palette's standalone/hub button, sibling params and
empty state. One stale ✗ was a removed feature (A7-10 → ⊘).

**The 4 remaining ✗ (and 1 ~) are the genuine floor**, each blocked for a
concrete reason, not want of effort:

- **No deterministic handle (2 ✗, 1 ~):** A2-26 is an absence-proof with no line
  to break; A2-37 (node non-overlap) has no form both deterministic *and*
  mutation-sensitive across cytoscape's non-deterministic layouts; A2-25 (~) has
  no observable distinct from A2-24 (`ixVisibility` owns a map's visibility).
- **Palette, near-vacuous (1) + unbuilt (1):** A8-12 needs an initial list taller
  than the 46vh max to make "first row visible on open" non-trivial — a 20+
  bundle registry hub — and even then the active row starts at index 0, so it
  sits at the top anyway (the test would assert a tautology). A8-16 (help
  focus-trap) is *unbuilt* — building it is a product change, not a testing task.

**There is no remaining move that yields a trustworthy test.** Every row with a
clean, deterministic, mutation-checkable handle is closed — including a long tail
that earlier passes wrongly filed as impossible: the zoom floor (a 100-node ring
fixture), fullscreen (an API spy), the count-up (a `waitForFunction` across the
600 ms window), orientation (a dispatched event), the lazy index and its fallback
(a `route` on the MiniSearch CDN), and the palette rows (read straight off stable
code). What is left would require a contract with no line to break (A2-26, A2-37,
and the `~` A2-25), a near-vacuous test behind a 20+ bundle hub whose active row
is at index 0 anyway (A8-12), or building an unbuilt feature (A8-16). The first
two would certify nothing and the third is a product change, not a test — each is
a documented hole on purpose. **Update the Cov column and the tallies here as
rows close** — this file is the source of truth for what is proven.

**Trust check:** "fully covered" is reached when every reachable row is ✓ or
consciously marked a documented hole. At 176/181 (97%) that point is reached: the
4 ✗ and 1 ~ are each annotated with the specific blocker that stops a trustworthy
test, not a missing one. Trust the **net-live list here (181)**, not a single
round number.

## Method

```bash
git log --follow --format="%h|%ad|%s" --date=short -- lib/okf/render/graph/template.html.erb
```

49 commits, each read in full — message body and template diff — and reduced to
the contract rows above of the form *(id, commit, type, behavior, handle,
coverage)*. The handle column is what makes a row actionable: a behavior with a
concrete `aria-pressed`/`getComputedStyle`/class target becomes a spec directly.
Coverage was assigned by cross-referencing each contract against the 23 spec
files at HEAD. Re-run the walk when the template gains commits, and add the new
contracts as rows.
