# What the suite covers, measured against the page's history

The graph page has 44 commits behind it. Reading every one of them yields a
catalog of roughly **230 user-visible behavioral contracts**, of which about
**94 are regression fixes** — bugs that actually shipped, were noticed, and
were repaired. A regression fix is the sharpest possible test target: it is a
failure mode already proven to be reachable in this codebase, by this author,
in this file.

Measured against that catalog, the suite covers **10 of ~94 regression fixes**
— roughly 11%.

That number is the point of this document. The suite is not weak where it
looks; it is strong on the interaction spine and absent on the periphery, and
the periphery is where most of the history's bugs actually lived.

## The headline, by area

| Area | Regression fixes in history | Covered |
|---|---:|---:|
| Graph canvas, camera, layout, emphasis | 23 | 1 |
| Files view + file tree | 28 | 1 |
| Inspector, links, escaping | 19 | 5 |
| Mobile / responsive layout | 7 | 1 |
| First-visit notes | 7 | 1 |
| Command palette, help sheet, search keys | 5 | 0 |
| Diagram viewer, deep links, index-layer styling | 5 | 0 |

Two structural facts explain the shape:

**The suite tests state, not rendering.** It asserts `data-view`,
`aria-pressed`, `data-side`, node counts and computed widths. Almost every
uncovered graph fix is about *how the canvas looks after an operation* —
whether dimming outranks a base style, whether the camera moved once or twice,
whether a layout ran twice and raced itself. Those need a different kind of
assertion (Cytoscape style resolution, settled positions, animation counts),
and the suite has one such helper (`settledBox`) written only because a bug
forced it.

**The suite tests the graph view.** Files is the single largest surface in the
template and the single largest source of historical bugs — 28 of 94 — and the
suite touches it with two assertions.

## The uncovered fixes, ranked

Ranked by what a repeat would cost, not by how easy the test is.

### 1. ~~Body sanitization~~ — **done**

`markdown-sanitized` (d1b485d), `js-esc-covers-quotes` (c2cedb6) and
`ruby-escape-covers-quotes` (adf96ff) are now covered by
`specs/sanitization.spec.js` against `fixtures/hostile`, in both render modes,
and all three were mutation-checked. See
[server-trust-boundary](../../.okf/design/server-trust-boundary.md) for the
mutation table.

One finding worth carrying into any extension of that fixture: with the
sanitizer removed, the `<script>` payload did not fire — `innerHTML` does not
execute script tags — and only `<img onerror>` did. A fixture of script tags
alone would have gone green against a page with no sanitizer at all.

### 2. Camera and layout races

Four fixes, all invisible to state assertions, all previously shipped broken:

- `one-camera-move-per-click` (ed6c0af) — the pan must fire once, deferred
  until the panel transition settles. It shipped firing twice.
- `mode-switch-one-click` (456aa79) — index layer off + tree mode on ran two
  layouts against one canvas; the tree landed wrong and needed a second click.
- `ix-fetch-ticketed` (456aa79) — a stale `/index` promise could add index
  nodes inside file-tree mode.
- `uncluster-restores-layout` (adf96ff) — un-clustering hardcoded a cose run
  and discarded whichever layout the select was on.

These are the bugs the current suite is least equipped to see and the ones
most likely to recur, because they are timing, not logic. `settledBox` is the
beginning of the tooling; a position-snapshot helper and a layout-run counter
would finish it.

### 3. Dim and highlight ordering

`dim-beats-tree-edges`, `dim-beats-ix-edges`, `dim-beats-parent-boxes`
(138b705). Cytoscape resolves equal-specificity selectors by array order, so a
rule declared after `.dim` silently defeats it. The whole emphasis system —
the thing that makes selection legible — failed this way for tree edges and
index edges at once.

Testable directly: `cy.$('edge.tree.dim').style('opacity') === 0.1`. Three
one-line assertions for a class of bug that is invisible on inspection and
recurs every time a style rule is appended to that array.

### 4. The file tree's collapse state machine

Six fixes, all about collapse and fold interacting badly:
`tree-collapse-honored-while-filtering` (0e9eab8),
`foldall-excludes-root` / `foldall-reads-whole-tree` (4b80b80),
`reopen-undoes-root-collapse` / `reopen-preserves-file-collapse` (2163bfe),
`root-collapse-folds-list-mobile` (aeef15b).

`collapsedDirs`, `foldedByRoot`, `ixOnly` and `.tree-min` are four pieces of
state that must agree, and the history shows them disagreeing repeatedly. The
2163bfe pair is the clearest: collapsing the root folded the list, and the
button the reader had just used could not bring the tree back.

### 5. Indexes-only, which flipped twice

`ixonly-releases-on-concept` and `ixonly-survives-map` (c7bb1b5) — the rule
was inverted in both directions at once: opening a concept kept a filter that
hid it, and opening a map cleared the filter being browsed. Also
`log-no-graph-button` (c7bb1b5), where a log's graph button opened the *root
index's* node — answering about a different file.

Two clicks and two `aria-pressed` reads each. Among the cheapest tests on this
list.

### 6. Link resolution

`link-to-index-resolves`, `link-to-log-resolves`,
`link-to-bare-directory-resolves` (ae7a882), `unresolvable-links-disabled`
(ed6c0af), `synthesized-dir-renders-listing` (ae7a882).

The suite covers exactly one link case — a concept-to-concept body link. The
fixture already has index links, a log, and a synthesized directory, so most
of this needs no new fixture at all.

### 7. Mobile layout regressions

`tools-sheet-two-columns`, `tools-sheet-no-orphan` (dec7cad),
`mobile-layout-select-fills-wrapper`, `mobile-layout-select-clickable`,
`mobile-icon-row-grouped` (a5f12ab), `ftree-header-one-layout` and its two
siblings (b376e8c), `ident-ellipsizes` (adf96ff).

These are the most recent fixes in the history — the last three commits before
this suite existed — which says the area is still moving. They are also the
most mechanically testable things on this list: `flexBasis`, `justifyContent`,
`marginLeft`, and counting distinct `getBoundingClientRect().top` values to
prove there is no orphaned row. `a5f12ab` even has a functional half worth
pinning: clicking the chevron area must actually change the layout, because it
used to land on dead space.

### 8. Untouched surfaces

No spec reaches any of these at all:

- **Command palette** (⌘K) — 4 fixes, including one where the Index row
  called `setView('index')` on a view that does not exist and blanked the page.
- **Help sheet** (`?`) — modal focus management, and `search-key-scoped`,
  where `/` focused a box that was hidden.
- **Theme toggle** — persistence, no-flash boot, Mermaid re-theming.
- **Deep links** — `?select=`, `?layout=`, `?view=`, `#hash`, and
  `deeplink-node-carries-view`, a fix for selecting into a view nobody is
  looking at.
- **Splitters** — drag, window-bound tracking, persistence, dblclick reset,
  and the viewport clamp that stopped a desktop width swallowing a phone.
- **Diagram viewer** — pan/zoom, focus return, and
  `diagram-viewer-rerenders-source`, where cloning the SVG lost its colors.
- **Catalog and Tags interiors** — cards, chips, empty states, card-to-graph
  navigation, tag multi-select.
- **Stats bars** — clicking one jumps to the graph, clears filters, isolates
  that type and fits.

Counted as element IDs rather than behaviors: of 43 actionable controls
(`<button>`, `<input>`, `<select>`) in the template, **27 are referenced by no
spec** — 63%.

## What this does not say

The suite is not worthless at 8%. It found a real bug on its first run, it
covers the paths a reader walks most, and its console-error watch is a
blanket check no per-behavior test provides: any of these uncovered surfaces
that throws during a covered flow still fails the run. The point of the
measurement is direction, not judgement — it says the next specs should go to
Files, sanitization, and canvas emphasis, and not to more view switching.

Two honest caveats about the number itself:

- **The catalog was built by reading commit messages and diffs**, and this
  repo's messages are unusually explicit about what was broken. Where a
  message was ambiguous the behavior was counted as a feature, so 94 is a
  floor, not a ceiling.
- **Some fixes are no longer reachable.** A few behaviors were reverted or
  superseded later in the history (the 4b80b80 landing-page work, mostly
  undone by cc7d545; `open-map-no-dim`, reverted by 9158ca6). Those are
  excluded from the 94, but the boundary is a judgement call in two or three
  cases.

## Method

```bash
git log --follow --format="%h|%ad|%s" --date=short -- lib/okf/render/graph/template.html.erb
```

44 commits, read in full — message body and diff — and reduced to behavior
rows of the form *(id, behavior, DOM/CSS handle, feature|regression-fix,
what was wrong)*. The handle column is what makes a row actionable: a
behavior with a concrete `aria-pressed` or `getComputedStyle` target can be
turned into a spec directly, and roughly four fifths of the catalog has one.
