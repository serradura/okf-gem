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
  views.spec.js        the rail, the number keys, canvas resize on return
  inspector.spec.js    open/close/widen, content, link following, focus chips
  filters.spec.js      chips, badge, search, and how they compose
  graph-modes.spec.js  cluster / tree / index layers, layouts, fit
  responsive.spec.js   the ≤768px drawer and sheet, in computed CSS
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

Add to it rather than bending a spec toward what it already makes easy. Check
edits with `ruby -Ilib exe/okf validate test/browser/fixtures/bundle` and
`lint` — both must stay clean, since a warning here would teach the suite to
tolerate one.

## How much of the page this actually covers

[COVERAGE.md](COVERAGE.md) measures the suite against the page's own history:
44 commits, ~230 behavioral contracts, ~94 of them fixes for bugs that really
shipped. The suite covers **10 of those 94**. It is strong on the interaction
spine (view switching, filters, inspector, the mobile drawer) and on both XSS
defenses; it is absent on the periphery — Files, canvas emphasis and camera
timing — which is where most of the history's bugs lived. Read it before
deciding what to write next.

`sanitization.spec.js` is the one to copy the shape of. It runs against
`fixtures/hostile`, a conformant bundle whose content attacks the page, and
its payloads set flags on `window` — so it asserts *the script did not run*
rather than *the markup looks clean*. All three defenses it covers were
mutation-checked by breaking them and watching it go red.

## Known bug, held open by a spec

`views.spec.js` carries one `test.fail()` — the graph collapses on return.
Dwell ~300ms or more on any other view, come back to Graph, and the graph
redraws at about a tenth of its size: a few dots in the top-left corner.
Reproduced in both render modes and confirmed by screenshot.

Both resize paths run and neither is sufficient. `setView`'s
`requestAnimationFrame(() => cy.resize())` fires while `#cy` is still 0×0, and
the canvas `ResizeObserver`'s 240ms debounce has already cached the collapsed
viewport by the time the container is back. A dwell of 0 passes because the
observer never fired — which is why the bug survived: clicking through the
rail quickly never reaches it.

`test.fail()` keeps the baseline green while holding the bug on the record.
Playwright reports it as an unexpected pass the moment it is fixed; delete the
marker then.

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
