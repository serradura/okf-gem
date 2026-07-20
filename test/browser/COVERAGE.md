# What the suite covers, measured against the page's history

The graph page has 44 commits behind it. Reading every one of them yields a
catalog of roughly **230 user-visible behavioral contracts**, of which about
**94 are regression fixes** — bugs that actually shipped, were noticed, and
were repaired. A regression fix is the sharpest possible test target: it is a
failure mode already proven to be reachable in this codebase, by this author,
in this file.

Measured against that catalog, the suite now covers roughly **38 of ~94
regression fixes** — about **40%**, up from 10 when this document was first
written. The climb came from working the ranked list below, gap by gap, each
new spec mutation-checked against the code it covers.

That number is still the point of this document. The suite is strong on the
interaction spine, the filters, the file tree, link resolution, both XSS
defenses and the mobile chrome; it is thin on canvas *timing* (the camera and
layout races) and absent on the diagram viewer. Read it before deciding what to
write next.

## The headline, by area

| Area | Regression fixes in history | Covered |
|---|---:|---:|
| Graph canvas, camera, layout, emphasis | 23 | 6 |
| Files view + file tree | 28 | 10 |
| Inspector, links, escaping | 19 | 10 |
| Mobile / responsive layout | 7 | 6 |
| First-visit notes | 7 | 1 |
| Command palette, help sheet, search keys | 5 | 3 |
| Diagram viewer, deep links, index-layer styling | 5 | 2 |

Two structural facts still shape it:

**The suite tests state, and now some geometry.** It asserts `data-view`,
`aria-pressed`, `data-side`, node counts and computed widths — and, since the
emphasis and mobile work, resolved Cytoscape opacities, `effectiveOpacity`,
`getBoundingClientRect` rows and settled node positions. What it still cannot
cheaply see is *how many times* the camera moved, which is the one camera fix
left uncovered.

**Files is no longer the hole.** It was the single largest surface and the
single largest source of historical bugs — 28 of 94 — and the collapse state
machine, the indexes-only filter and link resolution now reach ten of them.

## The specs that closed the gaps

Nineteen spec files, ~106 tests per render mode (212 total). Beyond the original
spine (`boot`, `views`, `inspector`, `filters`, `graph-modes`, `responsive`)
and `sanitization`:

- `emphasis.spec.js` — dim outranks a tree/index edge's own opacity (138b705),
  the highlight border, and **selection stays legible in cluster mode** (a bug
  this suite found — see below).
- `indexes.spec.js` — Indexes-only releases on a concept and holds on a map, the
  map graph button (c7bb1b5). Carries one held-open `test.fail` for the log
  graph button (a bug this suite found).
- `links.spec.js` — the inspector resolving a link to an index, the log, a bare
  directory's synthesized listing, and disabling the unresolvable (ae7a882,
  ed6c0af). Off a "See also" block in `runbooks/rollback.md`.
- `files-tree.spec.js` — the collapse state machine: honoured under a search,
  collapse-all excluding the root and reading the whole tree, and the mobile
  reopen that undoes a root collapse while preserving a file one (0e9eab8,
  4b80b80, 2163bfe, aeef15b).
- `mobile-layout.spec.js` — ident ellipsis, the two-column tools sheet with no
  orphaned icon, the layout select filling its wrapper, the one-line file header
  (adf96ff, dec7cad, a5f12ab, b376e8c).
- `camera-races.spec.js` — un-clustering restores the chosen layout (adf96ff)
  and the index→tree switch lands clean in one click (456aa79), both read from
  *settled* positions.
- `palette.spec.js`, `help.spec.js`, `deep-links.spec.js`, `theme.spec.js`,
  `interiors.spec.js`, `splitters.spec.js` — the surfaces no spec reached: the
  command palette (incl. the Index row that used to blank the page), the ? sheet
  and `/` scoping, `?view`/`?layout`/`?select`/`#hash`, the theme toggle's
  persistence, catalog/tags/stats navigation, and the inspector splitter's
  restore-clamp-reset-drag.

## Bugs this suite turned up

Writing the specs surfaced two real, shipped bugs the string-level tests could
not see. Both are now fixed:

1. **The log's graph button was visible when it should be hidden.**
   `openReserved('log',…)` sets `#fp-graph.hidden = true`, but the button is a
   `.btn.text`, and `.btn.text{display:inline-flex}` outranked
   `.btn[hidden]{display:none}` at equal specificity — so it rendered 143px wide
   with a stale click handler, the c7bb1b5 "different file" symptom back through
   CSS. Fixed with `.btn.text[hidden]{display:none}` (following the precedent at
   line 492) and pinned by a now-passing test in `indexes.spec.js` that was red
   before the rule.

2. **Selection was illegible in cluster mode** — `focusNode` dimmed the compound
   area boxes, whose opacity cascades to the nodes inside them, so the selected
   node and its neighbours faded too (measured effectiveOpacity 0.1). Reported by
   the maintainer, reproduced with a red test, fixed (dim leaves and edges, never
   `:parent`), and pinned by `emphasis.spec.js`.

## The uncovered fixes that remain

Ranked by what a repeat would cost.

### 1. one-camera-move-per-click (ed6c0af) — needs a move counter

The other three camera/layout races are covered; this one is not, and honestly
cannot be from the end state. Selecting a node opens the panel, whose
`cy.resize()` re-centres the whole graph and fires *last*, so the selected node
settles ~190px off centre whether or not `centerOn` ran (measured identical with
the pan removed). The fix is about *not moving twice*, which the settled state
cannot see. It needs a `cy.on('pan')` / animation counter — the "layout-run
counter" this document first called for. Until then, a test here would green
with `centerOn` deleted, which is worse than none.

### 2. The diagram viewer

`diagram-viewer-rerenders-source` (cloning the SVG lost its colours), pan/zoom,
and focus return on close. Untouched — it needs a fixture body carrying a
```mermaid``` block, and the viewer lazy-loads Panzoom and Mermaid from the CDN,
so a spec here trades determinism for CDN latency. Worth doing behind the same
`allowErrors`-free console watch, but scoped separately.

### 3. The remaining periphery

- **Command palette** — the bundle-switch half (hub mode) and ⌘⏎ new-tab are
  unreached; only the standalone view-jump path is covered.
- **Help sheet** — the modal focus *trap* (Tab cycling) is unchecked; open/close
  and `/` scoping are covered.
- **First-visit notes** — still one assertion; the hello2 "other views" note and
  the desktop hint are only dismissed, never asserted.
- **Index-layer styling** — `edge.ixe-syn` opacity, the synthesized-map hollow
  look, and `ixVisibility` hiding an emptied map.
- **Splitter drag persistence across reload**, and the files-tree splitter (only
  the inspector one is driven).

## What this does not say

The suite is not weak at 40%. It found two real bugs, fixed one, covers the
paths a reader walks most, and its console-error watch is a blanket check no
per-behaviour test provides: any uncovered surface that throws during a covered
flow still fails the run. The measurement is direction, not judgement — it now
points at camera timing and the diagram viewer, not at more view switching.

Two honest caveats about the number itself:

- **The catalog was built by reading commit messages and diffs**, and this
  repo's messages are unusually explicit about what was broken. Where a message
  was ambiguous the behavior was counted as a feature, so 94 is a floor. The
  "covered" column is a judgement call at the boundaries too — a few fixes are
  covered only in part (e.g. the layout select's clickable chevron is pinned via
  its width, not a click at the edge), and those are counted generously.
- **Some fixes are no longer reachable.** A few behaviors were reverted or
  superseded later in the history (the 4b80b80 landing-page work, mostly undone
  by cc7d545; `open-map-no-dim`, reverted by 9158ca6). Those are excluded from
  the 94.

## Method

```bash
git log --follow --format="%h|%ad|%s" --date=short -- lib/okf/render/graph/template.html.erb
```

44 commits, read in full — message body and diff — and reduced to behavior rows
of the form *(id, behavior, DOM/CSS handle, feature|regression-fix, what was
wrong)*. The handle column is what makes a row actionable: a behavior with a
concrete `aria-pressed` or `getComputedStyle` target can be turned into a spec
directly, and roughly four fifths of the catalog has one.
