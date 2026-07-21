# Browser suite

Drives `lib/okf/render/graph/template.html.erb` in a real Chromium. It exists
because the page's failure modes — a view that returns with a collapsed
canvas, a filter that stops composing with search, the ≤768px block folding
the wrong element, a handler that throws where nothing visibly changes — are
all invisible to a string assertion over the rendered HTML, which is what
`test/integration/render/` can do.

```bash
bundle exec rake browser:setup    # once: npm install + Chromium (~120MB)
bundle exec rake test:browser     # the suite, headless, ~50s
bundle exec rake serve            # the same fixture, yours to poke by hand
```

## Seeing it run

Four ways, in the order they are usually wanted:

```bash
bundle exec rake browser:ui               # the good one — spec list + live browser
bundle exec rake browser:watch            # a real window, 400ms per action
bundle exec rake browser:watch[filters,900]   # a different file, slower
bundle exec rake browser:video[responsive]    # record to .webm instead
bundle exec rake browser:report           # last run's traces and screenshots
```

`browser:ui` is Playwright's own runner: pick specs, watch them drive the
page, then scrub back and forth through the recorded steps with the DOM at
each one. It also records what you do by hand into a new spec.

`watch` and `video` take a spec-file filter and a slow-motion delay, and
default to one file against the live server — headed mode opens a window per
worker, and the whole suite at watchable speed is minutes of flashing windows.
Both read their knobs from `OKF_SLOWMO` and `OKF_VIDEO` in the config, so
`OKF_VIDEO=1 npx playwright test` works too if you want the whole suite
recorded.

`report` is the one to reach for after a failure — and it is what the CI job
uploads, so a red run there is inspectable without reproducing it locally.

Not part of the default `rake` task — it needs node, which has no place on the
Ruby 2.4 matrix, and the gem gains no dependency from it. CI runs it in a
separate **non-blocking** job (`continue-on-error`), because the page boots
against a CDN and a jsdelivr hiccup should not gate a merge. The job still
shows red and uploads `.tmp/` (traces, screenshots, report) on failure, which
is how you tell a regression from a network blip.

Both the `webServer` command and the static render run through `bundle exec`.
A CI `setup-ruby` with `bundler-cache` installs rack and webrick under a
`BUNDLE_PATH` that a bare `ruby -Ilib` would not search; locally it resolves
the same gems either way.

## Two projects, every spec

Every spec runs twice, because the template renders in two modes that diverge
in a load-bearing way:

- **server** — `okf server` on 8899. Bodies, catalog, index and log are
  fetched from `/node`, `/catalog`, `/index`, `/log` on demand.
- **static** — `okf render` to `.tmp/graph.html`, loaded over `file://`.
  The same payloads are baked into `EMBED`.

A spec that passes in one proves nothing about the other. Where they honestly
differ the spec says so and asserts both answers — `filters.spec.js`'s
body-text search is the example: bodies are only in the index when they are
present, and they are only present in a static render.

The static page is rendered fresh in `global-setup.js` on every run, so it is
never a stale copy of the template.

## Layout

```
playwright.config.js   the two projects, the webServer that boots okf server
paths.js               shared by config and global-setup (kept apart to avoid a cycle)
global-setup.js        renders the static page
helpers.js             the `app` fixture, the console-error watch, the DOM readers
fixtures/bundle/       an OKF bundle shaped to reach the page's branches
specs/
  boot.spec.js         what the page owes on arrival
  views.spec.js        the rail, the number keys, no collapse from a hidden fit
  inspector.spec.js    open/close/widen, content, link following, focus chips
  filters.spec.js      chips, badge, search, and how they compose
  graph-modes.spec.js  cluster / tree / index layers, layouts, fit
  responsive.spec.js   the ≤768px drawer and sheet, in computed CSS
  sanitization.spec.js the two XSS defenses, driven by a hostile bundle
  emphasis.spec.js     dim/highlight ordering, and cluster-mode legibility
  indexes.spec.js      Indexes-only, and the reserved files' graph button
  links.spec.js        the inspector resolving index / log / dir / dead / external links
  files-tree.spec.js   the collapse state machine (desktop + mobile)
  mobile-layout.spec.js the ≤768px tools sheet and file header, in geometry
  camera-races.spec.js un-cluster restore, index→tree, and one-camera-move (via the __camCenters counter)
  palette.spec.js      the ⌘K command palette (standalone: jump to a view)
  palette-hub.spec.js  the ⌘K palette in hub mode (switch bundle)
  global-search.spec.js the ⌘K palette's Concepts group, over the hub's /search
  manager.spec.js      the hub's /b/ workspace manager (verdict edge, columns, phone)
  workspace.spec.js    the manager's registry forms, driven live (serial, own $OKF_HOME)
  help.spec.js         the ? sheet and the / search key
  deep-links.spec.js   ?view / ?layout / ?select / #hash
  theme.spec.js        the theme toggle and its persistence
  interiors.spec.js    catalog / tags / stats navigation into the graph
  splitters.spec.js    both splitters: restore, clamp, reset, drag, persistence
  first-visit.spec.js  the welcome + "other views" notes, and the canvas hint
  index-layer.spec.js  synthesized-vs-authored map edges, and ixVisibility
  diagram.spec.js      the fullscreen Mermaid viewer (open / close / focus)
```

`helpers.js` sits beside the config rather than inside `specs/` on purpose —
`specs/` is `testDir`, and a non-spec module in there is a file Playwright
scans and ignores on every run.

## The console watch

The `app` fixture fails a test if the page logged a console error or threw,
even when every assertion passed. That is the check that catches "I changed
the filter code and the catalog quietly stopped rendering" — a thrown handler
leaves the DOM in a plausible-looking state that assertions walk straight
past. A spec that expects an error opts out with `app.allowErrors()`.

## The fixture

`fixtures/bundle/` is a conformant, lint-clean OKF bundle — 8 concepts, 23
links, 5 types, 5 areas, 5 tags — shaped to reach branches the page has no
other way in to:

- `charter.md` at the root, so the area filter produces its `(root)` group.
- `services/index.md` authored but `datasets/` with none, so the index layer
  draws both a written map and a synthesized one.
- Tags that span areas (`core` on four concepts in three areas), so a tag
  filter cannot be mistaken for an area filter.
- `log.md`, so the Files view has a history entry to open.
- a "See also" block in `runbooks/rollback.md` linking to `/index.md`,
  `/log.md`, a bare directory and a non-existent one, so the inspector's four
  in-bundle link resolutions each have a real link to follow, plus a
  `# Citations` section with an external `https://` link — the fifth kind, which
  the inspector opens in a new tab rather than resolving. All keep validate and
  lint clean (directory and reserved-file links are not cross-links; the
  external link is cited, so it draws no "external link without citations" info).
- a ```mermaid block in `decisions/adr-001-postgres.md`, so the diagram viewer
  has a real diagram to render, open and close.

Add to it rather than bending a spec toward what it already makes easy. Check
edits with `ruby -Ilib exe/okf validate test/browser/fixtures/bundle` and
`lint` — both must stay clean, since a warning here would teach the suite to
tolerate one.

## How much of the page this actually covers

[COVERAGE.md](COVERAGE.md) is the per-contract map — every user-visible behavior
the page introduced across its 49-commit history, each marked covered / partial /
uncovered against a named spec, with a ranked worklist of what is still missing.
Of **182 net-live contracts** it covers **136 (75%)**, 11 partially, 35 not yet;
by the narrower regression-fix-only lens that is ~60 of ~94. Read COVERAGE.md
before writing a spec — the ✗ rows are the to-do list. It is strong on the
interaction spine, the filters, the file
tree, link resolution, both XSS defenses, the mobile chrome, the first-visit
notes, the index layer, the diagram viewer and both halves of the command
palette (down to the ⌘⏎ new-tab chord, the Mermaid re-theme and the
`prefers-color-scheme` boot). The last regression it closed —
one-camera-move-per-click — cost a **product change**: a test-only counter added
to the page (`window.__camCenters`), because no external observable could tell
the fix from the bug. The graph-collapse-on-return that used to sit here as a
`fixme` is now **fixed** — its cause turned out to be the boot fit landing on a
hidden canvas, not the resize race the note assumed — and pinned by a
deterministic spec. Read it before deciding what to write next.

`sanitization.spec.js` is the one to copy the shape of. It runs against
`fixtures/hostile`, a conformant bundle whose content attacks the page, and
its payloads set flags on `window` — so it asserts *the script did not run*
rather than *the markup looks clean*. All three defenses it covers were
mutation-checked by breaking them and watching it go red.

## Bugs this suite found

Writing the coverage turned up three real, shipped bugs no string assertion could
see. All three are now fixed.

`emphasis.spec.js` pins the first: selecting a node in cluster mode used to fade
the whole graph. `focusNode` dimmed the compound area boxes, and a compound
parent's opacity cascades to the nodes inside it, so the selection and its
neighbours faded too (measured `effectiveOpacity` 0.1). The fix dims leaves and
edges, never `:parent`.

`indexes.spec.js` pins the second: a **log's "Open in graph" button stayed
visible** though the code sets `hidden=true`, because `.btn.text{display:
inline-flex}` outranked `.btn[hidden]{display:none}` at equal specificity — the
c7bb1b5 "different file" symptom back through CSS. Fixed with
`.btn.text[hidden]{display:none}` (the precedent at line 492); the test was red
before the rule and green after.

`views.spec.js` pins the third — and it is the one whose cause was **misdiagnosed
for months**. The graph collapsed on return: dwell on another view, come back,
and the graph redrew at a tenth of its size, a few dots in the top-left. The
held-open note blamed a resize race (setView's rAF firing at 0×0, the
ResizeObserver's 240ms debounce). Tracing it with the browser tools told a
different story: the single zoom animation that ran was a **fit**, not a resize.
`fitGraph` reads the container's own width to compute the zoom, and the one-shot
boot fit scheduled 400ms after load (`setTimeout(fitGraph, 400)`) fires on
whatever view you are on by then. Leave the graph inside that window and it fits
a hidden 0×0 canvas, where `(w-2*pad)/bb.w` goes negative and the zoom clamps to
minZoom — and stays there on return. The fix guards `fitGraph` to skip a canvas
with no size (the template already knew the hazard: it excluded the `?view=`
deep-link start for exactly this reason, just not the navigate-away case). The
spec fires that hidden fit by hand and asserts the zoom is untouched — red before
the guard, green after, in both render modes.

The misdiagnosis is the lesson: the old repro's load-sensitivity (deterministic
alone, flaky under parallel workers) was not noise to route around with a
`fixme` — it was the symptom pointing at a *timer racing boot*, not a resize
racing layout. Reading the actual animation, not the plausible mechanism, is what
found it.

## Writing a spec

Read the page first, assert second. Run the real thing, print what it actually
renders, and assert *that* — the four assertions that failed on this suite's
first green run were all cases of asserting what the code looked like it did:

- The panel labels are `Links to3` / `Linked from4` in the markup; the caps on
  screen are `text-transform`, which `toContainText` does not apply.
- The Index rail item runs `readIndex()` — `setView('files')` plus opening
  `index.md` in the reader. It does not press the index-only filter beside it.
- `#side` transitions its width over .22s, so a bare `getComputedStyle` read
  lands mid-animation. Use `toHaveCSS`/`expect.poll`, which retry.
- Eight nodes fit at `maxZoom`, so a correct "fit" can leave the zoom
  unchanged. Assert the rendered bounding box is inside the viewport, which is
  what fit actually promises.
