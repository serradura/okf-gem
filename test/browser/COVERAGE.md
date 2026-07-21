# What the suite covers, measured against the page's history

The graph page has 44 commits behind it. Reading every one of them yields a
catalog of roughly **230 user-visible behavioral contracts**, of which about
**94 are regression fixes** — bugs that actually shipped, were noticed, and
were repaired. A regression fix is the sharpest possible test target: it is a
failure mode already proven to be reachable in this codebase, by this author,
in this file.

Measured against that catalog, the suite now covers roughly **50 of ~94
regression fixes** — about **53%**, up from 10 when this document was first
written. The climb came from working the ranked list below, gap by gap, each
new spec mutation-checked against the code it covers.

The last round moved the number by one, and it is worth being precise about why
only one. The ⌘⏎ new-tab chord, the Mermaid re-theme and the
`prefers-color-scheme` boot fallback landed in the command-palette and diagram
areas, which were already at their regression-fix ceiling — so they are feature
coverage on a maxed area, not new points on the 94. `one-camera-move-per-click`
is the point that moved: it was the #1 *uncovered* regression fix, and it is now
covered — but only by a deliberate product change, a test-only counter added to
the page (see below), because no external observable could pin it.

The suite is strong on the interaction spine, the filters, the file tree, link
resolution, both XSS defenses, the mobile chrome, the first-visit notes, the
index layer, the diagram viewer and both halves of the command palette. The
graph-collapse-on-return that used to sit here as a held-open `fixme` is now
**fixed and pinned** — its cause was the boot fit landing on a hidden canvas, not
the resize race the note had assumed (see the bugs section below). Read this
before deciding what to write next.

## The headline, by area

| Area | Regression fixes in history | Covered |
|---|---:|---:|
| Graph canvas, camera, layout, emphasis | 23 | 7 |
| Files view + file tree | 28 | 11 |
| Inspector, links, escaping | 19 | 10 |
| Mobile / responsive layout | 7 | 6 |
| First-visit notes | 7 | 5 |
| Command palette, help sheet, search keys | 5 | 5 |
| Diagram viewer, deep links, index-layer styling | 5 | 5 |

Two structural facts still shape it:

**The suite tests state, geometry, and — now — one page-side signal.** It
asserts `data-view`, `aria-pressed`, `data-side`, node counts and computed
widths — and, since the emphasis and mobile work, resolved Cytoscape opacities,
`effectiveOpacity`, `getBoundingClientRect` rows and settled node positions.
*How many times* the camera moved is the one thing no external read could see;
it is now readable because the page carries a test-only counter
(`window.__camCenters`) for exactly that. Instrumentation, not a cleverer
assertion, is what closed it — the honest cost of pinning a sub-frame timing
contract.

**Files is no longer the hole.** It was the single largest surface and the
single largest source of historical bugs — 28 of 94 — and the collapse state
machine, the indexes-only filter and link resolution now reach ten of them.

## The specs that closed the gaps

Twenty-three spec files, 125 tests per render mode (250 total, all passing — the
held-open graph-collapse `fixme` is now a normal test since the fix). Beyond the
original spine (`boot`, `views`, `inspector`, `filters`, `graph-modes`,
`responsive`) and `sanitization`:

- `emphasis.spec.js` — dim outranks a tree/index edge's own opacity (138b705),
  the highlight border, and **selection stays legible in cluster mode** (a bug
  this suite found — see below).
- `indexes.spec.js` — Indexes-only releases on a concept and holds on a map, the
  map graph button (c7bb1b5), and a log *hiding* its graph button — the bug this
  suite found, now a passing test since the `.btn.text[hidden]` fix.
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
  *settled* positions; and **one-camera-move-per-click** (ed6c0af) — a
  panel-opening click commits exactly one centre-pan, and the *deferred* one —
  read off the `window.__camCenters` counter at the synchronous instant after
  the tap, the one moment that tells the fix from the immediate-pan bug.
- `palette.spec.js`, `palette-hub.spec.js`, `help.spec.js`, `deep-links.spec.js`,
  `theme.spec.js`, `interiors.spec.js`, `splitters.spec.js` — the surfaces no
  spec reached: the command palette's view-jump path (incl. the Index row that
  used to blank the page) *and* its bundle-switch path (a hub the config boots
  from two bundles, so /b/bundle/ carries a sibling) — including the **⌘⏎
  new-tab chord**, which a bundle row honours (window.open) where a view row
  ignores it — the ? sheet with its focus management and `/` scoping,
  `?view`/`?layout`/`?select`/`#hash`, the theme toggle's persistence, the
  no-flash boot, catalog/tags/stats navigation, and both splitters.
- `diagram.spec.js` — beyond open/close/focus, that **toggling the theme
  re-renders the inline diagram**: `rethemeMermaid` re-initializes Mermaid and
  re-runs each block, so a diagram rendered under the old theme is not left with
  its old fills.
- `first-visit.spec.js` — the welcome note, "Read the index", the canvas hint
  standing down while it is up, dismissal persistence, and the mobile "other
  views" note that fires on leaving the graph.
- `index-layer.spec.js` — a synthesized map's edges drawn fainter than an
  authored one's (`edge.ixe-syn` 0.3 vs `edge.ixe` 0.5), and a map whose
  concepts are all filtered away leaving the canvas (`ixVisibility`).
- `diagram.spec.js` — a Mermaid block opens the fullscreen viewer (re-rendered
  from source, focused), and Escape closes it and returns focus. Leans on the
  Mermaid + Panzoom CDN, so it fails on a jsdelivr hiccup — the reason the CI job
  is non-blocking. Off a ```mermaid block in `decisions/adr-001-postgres.md`.

## Bugs this suite turned up

Writing the specs surfaced three real, shipped bugs the string-level tests could
not see. All three are now fixed:

1. **The graph collapsed on return, and the cause was misdiagnosed for months.**
   Dwell on another view, come back, and the graph redrew at a tenth of its size.
   The held-open note blamed a resize race; tracing the one zoom animation that
   actually ran showed it was a **fit**. `fitGraph` computes the zoom from the
   container's own width, and the boot fit (`setTimeout(fitGraph, 400)` after
   load) fires on whatever view is up by then — leave the graph inside that
   window and it fits a hidden 0×0 canvas, `(w-2*pad)/bb.w` goes negative, and the
   zoom clamps to minZoom, staying there on return. Fixed by guarding `fitGraph`
   to skip a canvas with no size (the template already guarded the `?view=`
   deep-link start for this exact reason, just not the navigate-away case), and
   pinned by a deterministic `views.spec.js` test that fires the hidden fit by
   hand and asserts the zoom is untouched — red before the guard, green after,
   both modes. The lesson is in "the last camera fixes" below: the load-sensitive
   flake was the symptom of a *timer racing boot*, not noise to route around.

2. **The log's graph button was visible when it should be hidden.**
   `openReserved('log',…)` sets `#fp-graph.hidden = true`, but the button is a
   `.btn.text`, and `.btn.text{display:inline-flex}` outranked
   `.btn[hidden]{display:none}` at equal specificity — so it rendered 143px wide
   with a stale click handler, the c7bb1b5 "different file" symptom back through
   CSS. Fixed with `.btn.text[hidden]{display:none}` (following the precedent at
   line 492) and pinned by a now-passing test in `indexes.spec.js` that was red
   before the rule.

3. **Selection was illegible in cluster mode** — `focusNode` dimmed the compound
   area boxes, whose opacity cascades to the nodes inside them, so the selected
   node and its neighbours faded too (measured effectiveOpacity 0.1). Reported by
   the maintainer, reproduced with a red test, fixed (dim leaves and edges, never
   `:parent`), and pinned by `emphasis.spec.js`.

## The last camera fixes: one closed by instrumentation, one by reading the animation

### 1. one-camera-move-per-click (ed6c0af) — closed, but only by a page-side counter

This was the suite's documented hole, and how it was finally closed is worth
recording, because the failed attempts explain why the closure cost a product
change. Every *end-state* observable was probed against a mutation that guts
`centerOn` (immediate pan, no defer), and none discriminated:

- **Settled node position** is identical either way (~190px off centre), because
  the panel's `cy.resize()` re-centres the whole graph and fires *last*.
- **`cy.on('pan')` bursts** (a >120ms gap starting a new burst) come out as one
  burst both ways — the two moves chain without a clean gap.
- **The span of pan-motion** is ~450ms in the fixed code, but under the mutation
  it only *sometimes* stretches to ~900ms: the second move is the resize
  re-centre, itself timing-dependent and often absent, so the span test greened
  against the gutted code.

The fix's contract is not *where* the node lands but *when and how often* the pan
commits, and the end state cannot see that. So the page now carries a test-only
counter, `window.__camCenters`, bumped just before each committed centre-pan —
invisible to users, there only to be read. `camera-races.spec.js` reads it at the
one moment that discriminates: the synchronous instant right after the tap,
before the 260ms defer could fire. Fixed code reads 0 there (the pan is
deferred); the immediate-pan bug reads 1. It then confirms the counter reaches 1
and never doubles. Mutation-checked by flipping the defer off (`if(false)`),
which turns that synchronous read from 0 to 1 and reddens the test in both modes.

This is the honest shape of the closure: the test could not be made cleverer, so
the page was made observable. A Tier-1 change — no behavior moved, one number
now exists for a test to read. Weigh that trade before reaching for it elsewhere:
instrumentation earns its keep when the contract is a sub-frame timing the end
state erases, and not otherwise.

### 1b. graph-collapse-on-return — closed by reading the animation, not the mechanism

Its sibling, and the more instructive close. It was held as a `test.fixme` on the
theory that the collapse was a resize race — `setView`'s return rAF firing at
0×0, the ResizeObserver's 240ms debounce — with a repro that was deterministic
run alone but load-sensitive under parallel workers. Both halves of that were
wrong. Trapping every zoom change through the round trip showed a *single* smooth
animation to minZoom, and trapping `cy.animate` showed its caller was `fitGraph`,
not any resize. The real bug: the boot fit (`setTimeout(fitGraph, 400)` after
load) fires on whatever view is up by then, and `fitGraph` reads the container's
own width — so leaving the graph inside that 400ms window fits a hidden 0×0
canvas and the zoom clamps to minZoom. The load-sensitivity was the tell all
along: under load, boot ran past 400ms and the fit landed while the graph was
still *visible*, so it fit correctly and the bug "vanished" — a timer racing
boot, not a resize racing layout.

Fixed by guarding `fitGraph` to skip a zero-size canvas, and re-pinned as a
normal (no longer `fixme`) `views.spec.js` test that fires the hidden fit
directly and asserts the zoom is untouched — deterministic in both modes because
it triggers the fit itself instead of racing the boot timer. No instrumentation
needed: unlike one-camera-move, this bug leaves a stable end-state signal (the
clamped zoom) once you know to read it.

### 2. The remaining periphery

Smaller — what is left after the ranked gaps were worked. Two of the entries
that stood here are now closed and moved to the list above; what remains needs
either a product change or an unbuilt feature:

- **Help sheet** — the modal focus *trap* (Tab cycling) is unchecked because the
  page does not implement one; open/close, focus-on-open, focus-restore-on-close
  and `/` scoping are covered. Testing it would mean building it first.
- **The deeper canvas timing** — beyond one-camera-move above, the finer
  emphasis/animation-count fixes in the 23-strong canvas area need a
  per-committed-move counter in the page, the same instrumentation that gap is
  waiting on.
- **Theme** — the toggle, its persistence, the no-flash boot and Mermaid
  re-theming are covered; only the initial `prefers-color-scheme` fallback (a
  feature, not a shipped regression) is unpinned.

## What this does not say

The suite is not weak at 53%. It found three real bugs and fixed all three,
covers the paths a reader walks most, and its console-error watch is a blanket
check no per-behaviour test provides: any uncovered surface that throws during a
covered flow still fails the run. The measurement is direction, not judgement —
what is left points almost entirely at sub-frame camera timing, and the one piece
of it that needed a page-side counter (one-camera-move) shows the honest cost of
that. Its former sibling, the graph-collapse-on-return, turned out not to need
one at all — once read as a fit rather than a resize, it left a stable signal and
was fixed at the source.

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
