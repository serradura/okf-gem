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
index-layer accent flip-flop, the 5× number-key remaps), **182 net-live contracts
are rowed** in the area tables below (superseded micro-contracts are summarised,
not individually rowed).

**Coverage of those 182 net-live contracts (tallied from the tables, they sum
exactly):**

| | Count | % |
|---|---:|---:|
| ✓ covered | **115** | 63% |
| ~ partial | 16 | 9% |
| ✗ uncovered | 51 | 28% |

The **51 uncovered** rows are the worklist: ~11 are REG fixes with existing
fixtures (Priority 1), ~25 are cheap FEAT coverage (Priority 2), ~7 need a new
fixture (Priority 3), and ~9 are hard/instrumentation/unbuilt (Priority 4).

### By area (covered / partial / uncovered)

| Area | ✓ | ~ | ✗ | Total |
|---|---:|---:|---:|---:|
| 1 — Boot, views, rail, view-switching, keyboard | 7 | 0 | 4 | 11 |
| 2 — Graph canvas, camera, layout, emphasis, cluster/tree/index-layer | 18 | 9 | 11 | 38 |
| 3 — Filters & search | 13 | 1 | 5 | 19 |
| 4 — Inspector, links, escaping/sanitization | 18 | 0 | 2 | 20 |
| 5 — Files view, file tree, reserved files | 12 | 3 | 13 | 28 |
| 6 — Mobile / responsive | 10 | 1 | 3 | 14 |
| 7 — First-visit notes | 5 | 1 | 4 | 10 |
| 8 — Command palette, hub, help, keyboard sheet | 11 | 0 | 5 | 16 |
| 9 — Deep links, theme, splitters, diagram, static/server, interiors | 21 | 1 | 4 | 26 |
| **Total** | **115** | **16** | **51** | **182** |

The two thinnest areas carry most of the gap: **Files/file-tree (13 ✗)** — the
largest surface and largest historical bug source — and **Graph canvas (11 ✗)**,
where several ✗ are sub-frame timing or reserved-mode rendering. Areas 4 and 9
(inspector/escaping, deep-links/theme/diagram) are effectively complete.

### The two counts, reconciled

An earlier version of this file measured **regression-fixes only** and reported
~50 of ~94. This version counts **all contracts** — features and regressions —
and classifies conservatively (ambiguous → FEAT), which is why its raw REG count
(54) is below that earlier 94: the old count split the big commits (ed6c0af,
adf96ff, 4f4aae4) into finer regression rows and counted some behavior-changing
features as regressions. **Neither is wrong; they measure different things.** The
page reads as "better covered" here (63%) precisely because features — many of
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
| A1-08 | d942471 | FEAT | `0` fits the graph (graph view only) | keydown `0` → `fitGraph` | ✗ | no spec presses `0` |
| A1-09 | d942471 | FEAT | `\` toggles the inspector | keydown `\` → `setSide` | ✗ | inspector toggle tested via button, not key |
| A1-10 | d942471 | FEAT | `f` toggles fullscreen | `#btn-full`, `requestFullscreen` | ✗ | fullscreen not exercised (hard in headless) |
| A1-11 | d942471 | FEAT | Reduced-motion disables transitions/count-up | `@media (prefers-reduced-motion)` | ✗ | never emulated; testable via `emulateMedia` |

## Area 2 — Graph canvas, camera, layout, emphasis, cluster/tree/index-layer

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A2-01 | d942471 | FEAT | Clicking a node selects: dim others, hl node+neighbourhood, open inspector, write hash | `.dim`/`.hl`, `location.hash` | ✓ | inspector › clicking a node; emphasis |
| A2-02 | 8ca455f | REG | Esc clears selection: drop dim/hl, forget hash | `deselect()`, keydown Escape | ✓ | inspector › Escape drops the selection |
| A2-03 | 138b705 | REG | `.dim`/`.hl` outrank a tree edge's own opacity (style array order) | `.dim` after `edge.tree` | ✓ | emphasis › dim outranks a tree edge |
| A2-04 | 138b705 | REG | `.dim` outranks an index-layer edge's opacity | `.dim` after `edge.ixe` | ✓ | emphasis › dim outranks an index-layer edge |
| A2-05 | 975a522 | REG | Cluster-mode selection stays legible (dim leaves/edges, never `:parent`) | `focusNode` `.not(':parent')`, effectiveOpacity | ✓ | emphasis › selection stays legible in cluster mode |
| A2-06 | d942471 | FEAT | Selected node carries the highlight border | `.hl` border-width/color | ✓ | emphasis › the selected node carries the highlight border |
| A2-07 | 9158ca6 | REG | One `focusNode` drives concept/folder/map emphasis identically | `focusNode(ele,opened)` | ~ | emphasis covers the concept path only |
| A2-08 | 9158ca6 | REG | Tapping a folder (`.dir`) node emphasises it (dim rest+hl) | tap handler `.hasClass('dir')`→focusNode | ✗ | no spec taps a folder node for emphasis |
| A2-09 | 9158ca6 | REG | Tapping a map (`.ix`) node emphasises it | tap handler `.hasClass('ix')`→focusNode | ✗ | no spec taps a map node for emphasis |
| A2-10 | d0b4fed/9158ca6 | REG | Opening a map in-graph (non-tree) emphasises it like a concept | `setIxNodes(true).then(focusNode)` | ✗ | uncovered (d0b4fed no-dim ⊘ by 9158ca6) |
| A2-11 | d942471 | FEAT | Cluster wraps areas in one compound parent each | `:parent`, `#btn-cluster[aria-pressed]` | ✓ | graph-modes › cluster wraps the concepts |
| A2-12 | d942471 | FEAT | Cluster undoes itself completely | `setClustered(false)` | ✓ | graph-modes › cluster undoes itself |
| A2-13 | d942471 | FEAT | Cluster disables the layout selector | `layoutSel.disabled` | ✗ | no spec asserts the select is disabled |
| A2-14 | 8ca455f | REG | A cluster box whose concepts are all filtered is hidden | `:parent` `display:none` in applyGraphFilter | ~ | graph-modes › a filter still applies inside cluster |
| A2-15 | 8ca455f | REG | Clustering re-applies the active filter before tiling | `setClustered`→`applyGraphFilter` first | ~ | graph-modes › a filter still applies inside cluster |
| A2-16 | ed6c0af | FEAT | Tree mode: folders-as-nodes, folder→child edges only, link edges hidden | `#btn-tree`, `node.dir`, `edge.tree`, `edge.linkhid` | ✓ | graph-modes › tree mode adds folder nodes and undoes |
| A2-17 | ed6c0af | FEAT | Tree and cluster are mutually exclusive; tree disables layout+cluster | `setTree`↔`setClustered` guards | ~ | graph-modes covers tree add/undo, not the guards |
| A2-18 | ed6c0af | FEAT | Folder nodes are unselectable and filter-exempt | `hasClass('dir')` guards | ✗ | uncovered |
| A2-19 | 1498a7c | REG | Tree folder nodes render as accent squares (like maps) | `node.dir,node.ix` background accent | ✗ | node fill color of tree dirs untested |
| A2-20 | 1498a7c | REG | Tree parent→child edges are dashed | `edge.tree` line-style dashed | ~ | emphasis asserts edge.tree opacity, not dash |
| A2-21 | aeef15b | FEAT | `#btn-ix` draws the index layer over any layout, flips pressed | `#btn-ix[aria-pressed]`, `cy.nodes('.ix')` | ✓ | graph-modes › the index layer adds the map nodes |
| A2-22 | aeef15b/456aa79 | FEAT | Authored map draws accent, synthesized faint+dashed | `node.ix` vs `node.ix-syn` | ~ | index-layer covers edges, not node fill |
| A2-23 | aeef15b | FEAT | Index edges dashed `.ixe`; synth `.ixe-syn` fainter | `edge.ixe` .5 vs `edge.ixe-syn` .3 | ✓ | index-layer › synthesized map's edges fainter |
| A2-24 | aeef15b | FEAT | A map with all concepts filtered hides; parent survives on a child | `ixVisibility()`, node `display` | ✓ | index-layer › a map whose concepts are all filtered away |
| A2-25 | aeef15b | FEAT | Index nodes are exempt from the graph filter | applyGraphFilter skips `.ix` | ~ | index-layer partial (ixVisibility only) |
| A2-26 | aeef15b | FEAT | Index nodes never modelled (absent from catalog/tags/types) | id prefix `ix::` | ✗ | not asserted absent from catalog |
| A2-27 | aeef15b/456aa79 | REG | Entering tree disables `#btn-ix` and tears down the layer | `#btn-ix[disabled]`, `setTree`→`setIxNodes(false)` | ✗ | uncovered |
| A2-28 | 456aa79 | REG | index→tree switch lands clean in one click (no competing layout) | `setIxNodes(on,relayout=false)` | ✓ | camera-races › index layer to tree mode |
| A2-29 | 456aa79 | REG | A stale `/index` fetch after a toggle/in-tree is dropped | `ixSeq` ticket guard | ✗ | server-mode race; needs delayed fetch |
| A2-30 | d942471 | FEAT | Layout selector: 5 built-in + 3 lazy, cose fallback on load fail | `#layout`, `ensureLayout` | ~ | graph-modes › switching layouts keeps nodes (fallback ✗) |
| A2-31 | adf96ff | REG | un-clustering restores the chosen layout (not hardcoded cose) | `cy.layout` name | ✓ | camera-races › un-clustering restores the chosen layout |
| A2-32 | d942471/f00cb66 | FEAT | Fit frames the visible nodes (gentle 450ms ease) | `#btn-fit`, `fitGraph` | ✓ | graph-modes › fit brings the whole graph inside |
| A2-33 | ed6c0af | REG | One camera move per selection (deferred single pan) | `centerOn`, `window.__camCenters` | ✓ | camera-races › a panel-opening click commits exactly one |
| A2-34 | 9ea6162 | REG | fitGraph skips a hidden 0×0 canvas (no collapse-on-return) | `fitGraph` clientWidth guard | ✓ | views › a fit fired while the graph is hidden |
| A2-35 | adf96ff | FEAT | Non-deep-linked graph auto-fits after load + on orientation | `load`/`orientationchange`→fitGraph | ~ | related to A2-34; orientation ✗ |
| A2-36 | adf96ff | FEAT | Zoom floor auto-relaxes so a big graph never grows past fit | `relaxZoom()`, `cy.minZoom` | ✗ | uncovered |
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
| A3-07 | dc83857 | FEAT | Tag chips capped at top-40 until the finder reaches all | chipRow tag cap | ✗ | uncovered (needs >40 tags fixture) |
| A3-08 | d942471 | FEAT | Closing the slide-over leaves the applied filter in force | `#filters` toggle | ✓ | filters › close leaves the applied filter in force |
| A3-09 | 562dba5 | FEAT | One MiniSearch full-text index shared by graph/catalog/files | `ftIndex`, `ftMatch()` | ✓ | filters › narrows the graph to matching concepts |
| A3-10 | 562dba5 | FEAT | Search matches the description, not only the title | `descOf`, boost.description | ✓ | filters › matches on the description |
| A3-11 | 562dba5 | FEAT | Body text searchable only in the static bake | body in index only when baked | ✓ | filters › body text is searchable only in the static render |
| A3-12 | 562dba5 | FEAT | Clearing the search restores every concept | applySearch('') | ✓ | filters › clearing restores every concept |
| A3-13 | 562dba5 | FEAT | A term nothing matches empties the graph | ftMatch empty | ✓ | filters › a term nothing matches empties the graph |
| A3-14 | 562dba5 | FEAT | Search composes with a chip filter | applyGraphFilter ∧ ftMatch | ✓ | filters › search and a chip filter compose |
| A3-15 | 562dba5 | FEAT | Multi-term AND, prefix, fuzzy (typo-tolerant) | searchOptions prefix/fuzzy/AND | ✗ | prefix/fuzzy not asserted (fuzzy=`--fuzzy` parity) |
| A3-16 | 562dba5 | FEAT | Substring fallback until the index is ready / CDN down | ftMatch null → includes | ~ | fallback exercised implicitly, not asserted |
| A3-17 | 562dba5 | FEAT | Lazy: index builds on first focus/keystroke | `onfocus`→buildFtIndex | ✗ | timing not asserted (flake source) |
| A3-18 | dc83857 | FEAT | Catalog filters by area & tag (not just type) + find box | `#cat-fareas`/`#cat-ftags` | ✗ | interiors covers type chip only |
| A3-19 | dc83857 | FEAT | Tags view Types/Areas filter, recounts over survivors | `#tag-filters`, tagMatch | ✗ | views asserts "5 distinct tags" only |

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
| A4-12 | ae7a882 | REG | Dead-link tooltip reads "not a file in this bundle" | `a.dead[title]` | ✗ | links asserts disabled, not the title text |
| A4-13 | ed6c0af | FEAT | External/absolute links open in a new tab | `window.open(_blank)` | ✗ | uncovered (catchable via page event) |
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
| A5-08 | 0e9eab8 | FEAT | Fold-all label/aria/disabled/icon reflect folders in view | `syncFoldAll()` | ✗ | states not asserted |
| A5-09 | 4b80b80 | FEAT | File tree nests directories by depth, parent above child | `subtree()`, `--d` padding | ~ | structure exercised, indentation not asserted |
| A5-10 | 4b80b80 | FEAT | A dir containing only sub-dirs still renders | `dirParents()` | ✗ | needs fixture (dir with only subdirs) |
| A5-11 | 4b80b80 | FEAT | Folder headers show only the last path segment | `dir.split('/').pop()` | ✗ | uncovered |
| A5-12 | 1093ae3 | REG | Reader header hidden when no file open (`.fp-head[hidden]`) | `.fp-head[hidden]{display:none}` | ✗ | **uncovered REG — same [hidden]-specificity class as the log-button bug** |
| A5-13 | 1093ae3 | FEAT | index/log rows sit at the top of their folder in the tree | `resIn(dir,depth)` order | ~ | reserved rows exercised, ordering not asserted |
| A5-14 | 1093ae3 | FEAT | "Indexes only" toggle narrows the tree to the authored layer | `#ftree-ixonly`, `ixOnly` | ~ | indexes covers release/hold, not the narrowing |
| A5-15 | c7bb1b5 | REG | Opening a concept releases the Indexes-only filter | openFile→`setIxOnly(false)` | ✓ | indexes › opening a concept releases the filter |
| A5-16 | c7bb1b5 | REG | Opening a map does NOT release the Indexes-only filter | openReserved (no setIxOnly) | ✓ | indexes › opening a map does not release |
| A5-17 | 646f3f5 | REG | "Open in graph" on a map jumps to its folder / draws that map | openMapInGraph, centerOn | ✓ | indexes › a map offers the graph button and it lands |
| A5-18 | c7bb1b5/815d5c1 | REG | A log hides its "Open in graph" button (`[hidden]` honoured) | `.btn.text[hidden]{display:none}` | ✓ | indexes › a log hides the graph button |
| A5-19 | 3376b9a | REG | Every file's graph button reads one static "Open in graph" | `#fp-graph .fpg-lbl` text | ✗ | label text/consistency not asserted |
| A5-20 | 1093ae3 | FEAT | Type/tag combos hide reserved files while set | `res` populated only if `!ft&&!fg` | ✗ | uncovered |
| A5-21 | ee4788a | REG | ixOnly renders reserved as a flat list at folder depth (no headers) | `.file[data-res]` `--d`, flatRes | ✗ | uncovered |
| A5-22 | ee4788a | FEAT | ixOnly row shows full path; full tree shows bare filename | `.rn` text vs `data-path` | ✗ | uncovered |
| A5-23 | ee4788a | REG | ixOnly fold-all reflects nothing to fold | `#ftree-foldall` disabled | ✗ | uncovered |
| A5-24 | ee4788a | FEAT | ixOnly with no matches shows an empty-state message | `.empty` text | ✗ | needs fixture |
| A5-25 | 8241cc2 | REG | A long tree-row path ellipsizes, doesn't push its badge off-edge | `.rn{min-width:0;overflow:hidden}` | ✗ | uncovered |
| A5-26 | d942471/dc83857 | FEAT | Files type & tag comboboxes (keyboard-navigable) filter the tree | `#file-type-combo`, `#file-tag-combo` (role) | ✗ | uncovered (no spec drives the comboboxes) |
| A5-27 | 05b2bbb | FEAT | Reserved files re-fetch fresh on open (a new log entry shows) | `LOGS=null` before getLogs | ✗ | server-mode; uncovered |
| A5-28 | 05b2bbb | FEAT | Folder sections fold/unfold; state ignored while filtering | `.ffolder.closed`, filtering guard | ✓ | files-tree › a collapsed folder stays collapsed |

## Area 6 — Mobile / responsive

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A6-01 | adf96ff | FEAT | ≤768px: rail becomes an off-screen drawer, ☰ opens it, backdrop closes | `#app.nav-open`, `#btn-menu`, `#nav-bk` | ✓ | responsive › the rail becomes a fixed drawer (+ hamburger/backdrop) |
| A6-02 | adf96ff | FEAT | ≤768px: topbar tools fold into a ⚙ sheet | `#btn-controls`, `#app.controls-open` | ✓ | responsive › the controls toggle folds the tools row |
| A6-03 | adf96ff | FEAT | Opening Filters folds the sheet away | ctlSet(false) | ✓ | responsive › opening Filters folds the sheet |
| A6-04 | adf96ff | FEAT | Nothing overflows the viewport horizontally | body scrollWidth | ✓ | responsive › nothing overflows |
| A6-05 | adf96ff | FEAT | ⚙ controls toggle is absent on the Stats view | `#app[data-view=stats] #btn-controls` | ✗ | uncovered |
| A6-06 | adf96ff | FEAT | ⚙ carries a filter-count badge mirroring the active filters | `ctlBadge()`, `.fbadge` | ✗ | uncovered |
| A6-07 | dec7cad | REG | Folded tools sheet is two even columns, no orphaned icon | flex-basis calc(50%-4px) | ✓ | mobile-layout › the folded tools sheet is two even columns |
| A6-08 | a5f12ab | REG | Mobile layout `<select>` fills its wrapper (chevron clickable) | `#layout` width:100% | ✓ | mobile-layout › the layout select fills its wrapper |
| A6-09 | a5f12ab | FEAT | Mobile icon-button row groups (no space-between) | `#graph-controls` gap only | ✗ | uncovered |
| A6-10 | b376e8c | REG | Tree header lays out identically at every width (one line) | `.ftabs`, margin-auto placement | ✓ | mobile-layout › the file-tree header stays on one line |
| A6-11 | b376e8c | REG | Pane-toggle flush with neighbours at every width | `#ftree-min` no margin-bottom | ~ | one-line covered, alignment not asserted |
| A6-12 | ??/mobile | REG | The ident ellipsizes instead of overflowing the bar | `.ident` ellipsis | ✓ | mobile-layout › the ident ellipsizes |
| A6-13 | f00cb66 | REG | Persisted splitter width clamped to 70% of viewport on restore | `Math.min(w,innerWidth*.7)` | ✓ | splitters › a stored width wider than the viewport is clamped |
| A6-14 | adf96ff | FEAT | ≤768px collapsing root also folds the stacked list to header | `treeMin(true)` | ✓ | files-tree (mobile reopen path) |

## Area 7 — First-visit notes

| ID | Commit | Type | Behavior | Handle | Cov | Spec / reason |
|---|---|---|---|---|---|---|
| A7-01 | cc7d545 | FEAT | A dismissible `#hello` welcome note rides the graph, "Read the index" | `#hello`, `#hello-go` | ✓ | first-visit › the welcome note shows |
| A7-02 | 3ce2284 | REG | "Read the index" opens root index.md in the reader (not the list) | `#hello-go`→readIndex | ✓ | first-visit › Read the index dismisses and opens the index |
| A7-03 | cc7d545 | FEAT | Dismissal remembered across visits | localStorage `okf-hello` | ✓ | first-visit › dismissing stays dismissed across a reload |
| A7-04 | 3ce2284 | FEAT | Canvas hint (`.ghint`) stands down while the note is up, restored on dismiss | `gh.style.visibility` | ✓ | first-visit › the canvas hint stands down / restores the hint |
| A7-05 | 3ce2284 | FEAT | A second `#hello2` note points at ☰ on leaving the graph (compact) | `#hello2`, setView hook | ✓ | first-visit › a second note points at the other views |
| A7-06 | cc7d545 | FEAT | The note belongs to the graph, disappears on other views | `#app:not([data-view=graph]) ~ #hello` | ~ | not asserted explicitly |
| A7-07 | 3ce2284 | FEAT | ☰ dismisses `#hello2` (only once on screen), remembered | hello2Done early-return | ✗ | uncovered |
| A7-08 | cc7d545/3ce2284 | FEAT | Note wording follows pointer type & width (tap/pinch, ☰ mention) | `@media (pointer:coarse)`/width | ✗ | uncovered |
| A7-09 | 3ce2284 | FEAT | `#hello` reflows for short & landscape-phone viewports | `@media (max-height:480px)` | ✗ | visual; uncovered |
| A7-10 | adf96ff | FEAT | A "best on desktop" `#mnote` shows on small screens, dismiss/persist | `#mnote`, `okf-mnote` | ✗ | uncovered |

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
| A8-09 | adf96ff | FEAT | ⇄ Switch rail button shown only in hub mode | `#btn-switch[hidden]` | ✗ | hidden-in-standalone not asserted |
| A8-10 | adf96ff | FEAT | Palette empty states: "no matches" vs only-this-bundle | `a.none` | ✗ | uncovered |
| A8-11 | adf96ff | FEAT | Sibling links carry current view+layout as query params | `target()` | ✗ | not asserted |
| A8-12 | 8241cc2 | REG | Palette first row is visible on open (unhide before render/scroll) | open() ordering | ✗ | uncovered |
| A8-13 | 01d39a5 | FEAT | `?`/help button opens a modal shortcut sheet listing bindings | `#kb`, `#btn-help` | ✓ | help › ? opens the sheet and lists the bindings |
| A8-14 | 01d39a5 | FEAT | Esc closes the sheet; a second `?` toggles it | kbClose | ✓ | help › Esc closes it |
| A8-15 | (suite) | FEAT | Help sheet manages focus: close on open, opener on close | focus mgmt | ✓ | help › the sheet manages focus |
| A8-16 | (unbuilt) | — | Help sheet focus *trap* (Tab cycling within modal) | — | ✗ | **feature does not exist** (Tier 3) |

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
| A9-16 | 357ae87 | FEAT | Viewer pan (drag), zoom (wheel/pinch/±), reset (btn/dbl-click) | `#dgv-in/out/reset`, panzoom | ✗ | pan/zoom/reset controls uncovered |
| A9-17 | 357ae87 | FEAT | While the viewer is open, other shortcuts are suppressed | keydown early-return | ✗ | uncovered |
| A9-18 | 357ae87 | FEAT | Mermaid blocks: zoom-in cursor, accent hover, focus outline | `.mermaid` CSS | ✗ | visual; uncovered |
| A9-19 | ed8a554 | FEAT | `EMBED` switches all five data reads: baked (static) vs fetched (server) | EMBED const | ✓ | proven by the two-project harness (every spec ×2) |
| A9-20 | ed8a554 | FEAT | Server getters hit endpoints (bodies never memoized → live edits) | fetch NODE/META | ~ | both modes run; live-edit reflection not asserted |
| A9-21 | d942471 | FEAT | Catalog cards: type chips, "X of Y" count, click → graph | `.card`, `#cat-cnt` | ✓ | interiors › a card opens that concept; views |
| A9-22 | d942471 | FEAT | Catalog type chip narrows the grid and its count | `.card` filter | ✓ | interiors › a type chip narrows the grid |
| A9-23 | d942471 | FEAT | Tags cloud: select lists concepts, second tag adds, click → graph | `.tcloud`, `#tag-detail` | ✓ | interiors › selecting a tag / a second tag adds |
| A9-24 | d942471 | FEAT | Stats count-up animation on the stat cards | `.stat` countUp | ✗ | visual; uncovered |
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
   stale handler. Fixed with `.btn.text[hidden]{display:none}`. **Note A5-12 in
   the worklist is the same `[hidden]`-specificity class, still uncovered** — the
   reader header (`.fp-head[hidden]`) — worth checking it is actually hidden.

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

---

## Uncovered worklist — what is still missing

Ranked by value × cheapness. **Tier-cheap** = writeable against existing or one
small new fixture, deterministic, no product change. **Needs-fixture** = add a
bundle/dir first. **Needs-instrumentation/hard** = no external handle, or a
product change, or genuinely untestable headless.

### Priority 1 — REG fixes, cheap, existing fixtures (write these first)

| ID | Behavior | Handle | Note |
|---|---|---|---|
| A5-12 | Reader header hidden when no file open | `.fp-head[hidden]{display:none}` | **Same `[hidden]`-specificity bug class as the log button** — a real REG, no spec. Open Files, open nothing / close a file, assert `#fp-head` `display:none`. |
| A2-08 | Tapping a folder node emphasises it | `focusNode` on `.dir` tap | Tree mode, emit tap on a `.dir` node, assert `.dim`/`.hl` + effectiveOpacity. |
| A2-09 | Tapping a map node emphasises it | `focusNode` on `.ix` tap | Index layer on, tap an `.ix` node, same asserts. |
| A2-13 | Cluster disables the layout selector | `#layout[disabled]` | Click cluster, assert `#layout` disabled + `#btn-tree` too. |
| A2-27 | Entering tree disables `#btn-ix`, tears down layer | `#btn-ix[disabled]`, `.ix` count 0 | Turn on ix, enter tree, assert btn-ix disabled and no `.ix` nodes. |
| A4-12 | Dead-link tooltip text | `a.dead[title]` | Extend links.spec: assert the disabled link's `title`. |
| A4-13 | External links open in a new tab | `window.open(_blank)` | Catch the context `page` event (like the ⌘⏎ test). Needs an external link in a fixture body. |
| A6-05 | ⚙ controls toggle absent on Stats | `#app[data-view=stats] #btn-controls` | Mobile viewport, go to Stats, assert hidden. |
| A6-09 | Mobile icon-button row grouping | `#graph-controls` no space-between | Assert computed justify-content. |
| A5-19 | One static "Open in graph" label | `#fp-graph .fpg-lbl` text | Open several files, assert the label is always "Open in graph". |
| A7-07 | ☰ dismisses `#hello2` once on screen | hello2Done early-return | Mobile, leave graph (note shows), open ☰, assert note gone + persisted. |

### Priority 2 — FEAT, cheap, existing fixtures

| ID | Behavior | Handle |
|---|---|---|
| A1-08 | `0` key fits the graph | keydown `0` |
| A1-09 | `\` key toggles the inspector | keydown `\`, `data-side` |
| A2-18 | Folder nodes unselectable + filter-exempt | tap `.dir` no select / filter skip |
| A2-25/26 | Index nodes filter-exempt / absent from catalog | applyGraphFilter skip / catalog |
| A2-36 | Zoom floor auto-relaxes | `cy.minZoom` after layout |
| A3-16 | Substring fallback before index ready | ftMatch null path |
| A5-08 | Fold-all label/aria/disabled/icon states | `syncFoldAll` |
| A5-11 | Folder headers show last segment only | header text |
| A5-13 | index/log rows at top of their folder | `resIn` order |
| A5-14 | "Indexes only" narrows the tree | `#ftree-ixonly` list contents |
| A5-25 | Long tree-row path ellipsizes | `.rn` overflow |
| A5-26 | Files type/tag comboboxes filter the tree | `#file-type-combo` (role) |
| A6-06 | ⚙ filter-count badge | `#btn-controls .fbadge` |
| A6-11 | Pane-toggle flush at every width | `#ftree-min` alignment |
| A7-06 | `#hello` disappears on other views | sibling combinator display |
| A8-09 | ⇄ Switch button hidden in standalone | `#btn-switch[hidden]` (assert in non-hub project) |
| A8-10 | Palette empty states | `a.none` |
| A8-11 | Sibling links carry view+layout | `target()` query on the row href |
| A8-12 | Palette first row visible on open | scroll position after open |
| A9-16 | Diagram viewer pan/zoom/reset controls | `#dgv-in/out/reset` |
| A9-17 | Viewer suppresses other shortcuts | keydown while open |
| A3-18 | Catalog area/tag filter + find | `#cat-fareas`/`#cat-ftags` |
| A3-19 | Tags view Types/Areas filter + recount | `#tag-filters` |
| A2-20 | Tree edges dashed | `edge.tree` line-style |
| A2-19 | Tree folder nodes accent | `node.dir` background |

### Priority 3 — needs a new fixture

| ID | Behavior | Fixture to add |
|---|---|---|
| A5-10 | Dir with only sub-dirs renders | a directory containing only subdirectories (no files) |
| A5-11 | (also helped by the above) | — |
| A3-07 | Tag chips capped at 40 | a bundle with >40 distinct tags |
| A5-21/22/23/24 | ixOnly flat list / full-path label / fold-all-empty / empty-state | reserved-file arrangements + a no-reserved dir |
| A9-20 | Server live-edit reflection | mutate a body file mid-test (server only) |
| A7-10 | `#mnote` best-on-desktop note | (exists; just needs a mobile spec that doesn't seed okf-mnote) |
| A3-15 | Prefix/fuzzy search | assert a typo'd query still matches (fuzzy=`--fuzzy` parity) |

### Priority 4 — hard / needs instrumentation / genuinely untestable headless

| ID | Behavior | Why hard |
|---|---|---|
| A1-10 | `f` fullscreen | `requestFullscreen` unreliable headless |
| A1-11 | Reduced-motion | needs `emulateMedia({reducedMotion})` — doable but low value |
| A2-29 | Stale `/index` fetch dropped (ixSeq) | server-only race; needs a delayed/throttled response |
| A2-30 | Layout cose-fallback on CDN failure | needs a blocked CDN route |
| A2-37 | Node spacing across layouts | pure visual, no clean handle |
| A5-27 | Reserved re-fetched fresh | server-only, timing |
| A9-24 | Stats count-up animation | visual/timing |
| A7-08/09, A9-18 | Note gesture wording / reflow, mermaid cursor/hover | pure visual polish |
| A8-16 | Help focus *trap* | **feature unbuilt (Tier 3)** — build it, then test |

---

## How to drive this to full coverage

1. **Work Priority 1 first** — REG fixes with existing fixtures, the sharpest
   targets. Each is one spec test, mutation-checked (break the handle, confirm
   red, restore). A5-12 especially: the same `[hidden]`-specificity bug class the
   suite already found twice.
2. **Then Priority 2** — mechanical FEAT coverage; batch by spec file
   (files-tree, graph-modes, responsive, palette get the most new tests).
3. **Priority 3** needs fixtures — extend `fixtures/bundle/` per AGENTS.md's
   "don't skimp on fixtures" rule; keep it validate+lint clean.
4. **Priority 4** — decide case by case; several are legitimately "documented
   hole" territory (log it, don't fake a test). A8-16 is a product decision.
5. Re-run `rake test:browser` after each; keep it deterministically green.
   **Update the Cov column and the tallies here as rows close** — this file is
   the source of truth for what is proven.

**Trust check:** "fully covered" is reached when every Priority-1/2/3 row is ✓ or
consciously marked a documented hole, and Priority-4 items are each either done,
instrumented, or explicitly logged as untestable. Trust the **net-live list here
(182)**, not a single round number.

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
