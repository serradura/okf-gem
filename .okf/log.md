# Update Log

## 2026-07-22
* **Update**: [graph-server](capabilities/graph-server.md) names a bundle by its
  slug. Every row that offered a choice between bundles — the ⌘K switcher, the
  Bundles panel, the hub's own `/b/` page — led with `Folder.label`, the derived
  `parent/dir` string, and put the slug in muted grey beside it. That is the
  address in the name's place: a bundle is addressed by `@okf-gem` and
  `/b/okf-gem/`, and the folder is where it happens to sit. In a registry of
  projects the label is also `…/.okf` on nearly every line, so the loudest column
  repeated the one word that tells no two bundles apart. `Folder.label` now reads
  a `.okf` directory as its parent (`repo/.okf` → `repo`), which fixes `okf
  registry list` and the default server title too; the rows carry `@slug` as the
  name, and the folder only where it is not the name repeated.
* **Correction**: the rail says **Index** while the root map is the open file.
  Index is a shortcut into Files, so the two share one `data-view` — and
  `activeRail()` read only that, which lit Files on the one screen a reader
  reached by asking for Index. The open file is what tells them apart, so it is
  what the rail reads.
* **Update**: [read-views](capabilities/read-views.md) records that `dirs` and
  `stats` answer about the *same* directories. Both read `Bundle#directory_index`
  now; grouping the catalog instead knew only the directories that happen to hold
  a concept, so the two verbs disagreed about how big a bundle was and — worse —
  `by_dir` omitted directories `--dir` answers about. A directory holding nothing
  directly reports the zero it holds, which is what makes `by_dir.keys` a
  complete list of what `--dir` can name. The same paragraph now covers `--area`
  refusing `--dir` as well as `--depth`: one reason wearing two shapes, since the
  deprecated flag is exact and both of the others select a range.
* **Update**: [graph-server](capabilities/graph-server.md) and
  [library-api](capabilities/library-api.md) record who names the search
  endpoint. The route answers on every app; *advertising* it is the caller's,
  because the page resolves it against the reader's URL and only the host knows
  its own prefix. A default of `"search"` — which this bundle briefly described —
  would have pointed an app mounted at `/knowledge` back at its host's root. The
  correction is worth keeping visible: the bug was invisible from inside the app,
  and only appears where the gem is a library rather than a command.

* **Correction**: [read-views](capabilities/read-views.md) records that `stats`
  and `dirs` count directories off one map. They did not: `stats` grouped the
  catalog, so it saw only directories holding a concept, while `dirs` reads
  `directory_index` — two verbs shipped in the same release answering "how many
  directories?" with 2 and 3 for the same bundle, neither flagged, so whichever
  one an agent asked was the one it believed. `by_dir` also omitted every
  directory it could not see, which meant `--dir deeply` answered about a
  directory nothing in `stats` said was there. Both now read `directory_index`,
  and a directory holding nothing directly reports its zero rather than vanishing.
* **Correction**: `Server::App`'s `search_endpoint` is a parameter again, not a
  default. It had been defaulted to `"search"` so `okf server` would advertise
  the route it had just gained — but the page resolves that string against the
  URL the reader is on, so an app mounted at `/knowledge` pointed its palette at
  the host's root. Only the caller knows where it was mounted; `okf server` names
  it, embedders name their own, and the route answers either way.
* **Correction**: the `/search` cap and engine live on
  [graph-server](capabilities/graph-server.md)'s `App` alone. `Hub` kept its own
  copies after the payload moved, so raising the cap in the obvious place would
  have changed nothing — a constant duplicated with its reasoning intact is the
  kind that drifts quietly.
* **Update**: [search](capabilities/search.md) and
  [search-engines](design/search-engines.md) record the prepared corpus. The
  server was rebuilding the whole index on every request — 1.45 s per search on a
  414-concept bundle, flat across repeats, because each one threw away what the
  last had built. This bundle had already predicted it: the build is ~95% of the
  index path's cost, and a long-lived server is exactly the case that amortizes
  it where a one-shot CLI cannot. `Search.prepare` holds a corpus and
  `Search.with` queries it, so a search is 0.016–0.052 s and the build lands at
  boot. The engine opts in by exposing `prepare`; the scan declares none and is
  handed none, so the seam cost no engine anything. The trade is staleness — a
  corpus is a snapshot — and the hub drops its own on any registry write, which
  is the bug this nearly shipped with rather than a precaution.
* **Update**: [graph-server](capabilities/graph-server.md) gains `/search` on the
  single-bundle app and loses `f`. The route was hub-only because it was
  conceived as the cross-bundle one, which left the mode most readers meet first
  with a palette that could not find anything; one bundle is a legal one-element
  set, so the assumption was the only obstacle. What followed is the interesting
  half: a row with **no slug** is a shape three places had never seen, and each
  read a missing slug as a *foreign* bundle — a `../undefined/` 404 on every
  result, an "undefined" chip, and a full page reload to reach a node already on
  screen. One absent field, three wrong answers, none of them where the change
  was made.
* **Update**: [graph-server](capabilities/graph-server.md) records three canvas
  behaviours a big bundle turns from cosmetic into structural — the force layouts
  settling once instead of rendering every tick of the simulation, a cluster box
  becoming scenery rather than the largest drag target on the page, and no form
  control under 16px where iOS Safari would zoom the view and not zoom back.
* **Update**: [read-views](capabilities/read-views.md) records three ways `--dir`
  could answer wrongly and exit 0: an ancestor chain handed back case-folded
  (so every ancestor of a capitalised directory vanished from the chain the flag
  exists to draw), a trailing slash refused (while the human views *print* one, so
  pasting a row back returned nothing), and `--area` with `--depth` unioning
  rather than narrowing. The shape they share is worth more than any of them:
  each was a rule written against one spelling of a directory and exercised only
  in that spelling.
* **Update**: [agent-skill](capabilities/agent-skill.md) converges on one first
  move. The skill named three different ones across seven places, which is the
  deliberation cost an agent pays on every retrieval — and the lookup table added
  to remove that cost duplicated the reference, contradicted its own file, and
  quoted measurements from a bundle no reader can open. Reverted, and the
  disagreement fixed by subtraction instead: `okf dirs` first, everywhere.
* **Update**: [browser-tests](design/browser-tests.md) gains what the cluster
  specs taught. Two of them passed against the bug on the first try — one
  assertion a compound parent satisfies by construction, one aimed at a region
  that falls through to the canvas — and a third waited a fixed duration for a
  layout that does not move anything while it computes. The residual flake is
  named rather than hidden, with the reason those two specs are the one place
  retries are legitimate.

## 2026-07-21
* **Update**: [read-views](capabilities/read-views.md) gains `--depth` and the
  `dirs` subtree count. Both came out of running the CLI against a bundle an
  order of magnitude bigger than this one, which is the only way the gap shows:
  every read view had a `--dir` and none had a way to ask for a *level*, so the
  §6 map — one section per directory — was hundreds of KB with no lever but
  naming each branch by hand. The subtree count is the half that is easy to miss:
  depth alone truncates a deep tree into a column of zeroes, because direct
  counts are honest and an intermediate directory holds nothing of its own. Two
  numbers per row, the second defined as what `--dir` on that row returns, so the
  view and the flag cannot drift apart.
* **Update**: [graph-server](capabilities/graph-server.md) records cluster mode
  nesting. The same rename reaches the page: a cluster is a directory, the boxes
  nest as the directories do to a depth the reader picks, and the filter chips
  list every dir rather than first segments. Two bugs came out of it, both of the
  shape this bundle keeps noting — a rule written for one level, exercised only
  at one level. The empty-box pass read a compound's *children*, so an
  intermediate box holding nothing but sub-boxes always read empty and took its
  whole branch off the canvas; and fcose, handed a nested graph whose nodes went
  `display:none` mid-animation, threw on a label it could no longer measure. The
  second one is the more interesting: it was only reachable by typing during the
  tiling, which is exactly the *other order* the phantom-box bug taught this
  bundle to look for, one release ago, in this same function.
* **Update**: [read-views](capabilities/read-views.md), [search](capabilities/search.md)
  and [graph](model/graph.md) now say `--dir` where they said `--area`, and
  read-views gains the `dirs` verb. The rename is not cosmetic: "area" appears
  nowhere in the OKF spec (`grep -ci area SPEC.md` → 0) — it was this gem's own
  word for a concept id's *first path segment*, and that projection threw away
  every level below it. The spec's word for grouping is *directories*, the value
  the catalog already carried on every row, so `dir` becomes the only machine
  word (full path, `.` at root, `(root)` for humans) and "cluster" stays prose
  for what a dir groups. `--area` and `tags --by area` keep their old exact
  behavior and warn, for one release.
* **Correction**: a maintain pass against `CHANGELOG.md` found the drift running
  the *other* way — the bundle was current and the changelog was not. Every
  concept touched by this branch's server/page work had its body updated in the
  same commit as the code (`bundles-manager`, `graph-server`,
  `server-trust-boundary`, `registry` all speak `--read-only`, and a search for
  `--allow-manage`/`--allow-edit` returns nothing), but `[Unreleased]` carried
  none of it: the registry's browser surface and its four write gates,
  cross-bundle search from the hub, the topbar box's count and bridge, the 404
  rebuilt as a directory, the touch preview card, and additive type chips were
  all shipped and undocumented. Written now, documenting the **net end state
  only** — the flag is `--read-only` with management as the default, and the
  intermediate `--allow-edit` → `--allow-manage` renames are deliberately not
  named, because neither ever appeared in a release and a changelog that
  describes states no user ever saw is a changelog nobody can use.
* **Correction**: two timestamps were stale by up to two days —
  [graph-server](capabilities/graph-server.md) stamped `07-19T03:00` with a body
  last edited `07-21T14:43`, and [bundles-manager](capabilities/bundles-manager.md)
  stamped `07-21T00:00` against `07-21T13:51`. The bodies were right both times;
  only the closeout's timestamp bump was skipped. Worth recording as a pattern
  rather than a slip: `timestamp` records *last written*, so a body edited in the
  same commit that leaves the stamp alone makes every freshness answer — a
  reader's, and `lint --stale-after`'s — quietly wrong in the direction that
  looks fine.
* **Update**: [browser-tests](design/browser-tests.md) gained the vendor cache's
  bypass (`OKF_NO_VENDOR_CACHE=1`). The cache itself was already documented down
  to the measurement that refuted its own rationale; the one lever a reader needs
  to check the template's pins against the real CDN was the part missing.
* **Addition**: the skill gained a **`refine` verb** and the CLI its two
  evidence views. `playbooks/refine.md` is the third authoring boundary —
  `curate` keeps the structure sound, `maintain` keeps the content true,
  `refine` changes where knowledge lives: the directory
  tree as a lossy projection of the link graph, cohesion over balance, concerns
  as tags never containers, free levers (heading sectioning, tag curation,
  extraction) before file moves, and a propose-don't-apply contract (a report
  plus a frozen execution prompt). The evidence is mechanical now: `okf tags
  --by` rows carry each tag's `count/total` so locality (domain vs concern)
  reads per row, and `okf graph --hubs` ranks inbound links grouped by source
  area — the hub origin test. The [read views](capabilities/read-views.md) and
  [agent skill](capabilities/agent-skill.md) concepts record both; the design
  came from evaluating a field report on a 50-concept production bundle whose
  restructuring had to be hand-derived.
* **Change**: the hub's 404 stopped leading with the apology. It is a directory
  reached by a wrong turn, not an error page, so the **asked path is now the
  heading** — mono, 27px, where a dropped slash reads as a shape — and "not
  found" is the eyebrow above it. A reader arrives already knowing they are
  lost; the URL bar told them. The near miss became a **row** instead of a
  sentence, wearing the same anatomy as the list under it and already lit, with
  `⏎` wired to it before a character is typed. Rows gained the folder, which is
  the fact that actually distinguishes bundles on a real server (`site/.okf`,
  `minifts/.okf`, `okf-core/.okf` are three titles that read alike). And colour
  went back to marking exceptions only: a healthy row draws no verdict edge,
  because six rules saying "nothing to report" is a page where the one that
  matters cannot be found by looking.
* **Fix**: the 404's ↑↓ keys are gone, and moving through the list is Tab's job
  again. The hand-rolled cursor was a second focus model living beside the real
  one — it lit rows the browser did not consider focused, it was invisible to a
  screen reader, and keeping the two in step is what left the near miss and a
  list row highlighted at once, which made ↑↓ read as doing nothing at all. Every
  row is an `<a href>`, a filtered-out row is `display:none` and leaves the tab
  order on its own, and Shift-Tab goes back: all of it free, none of it ours to
  maintain. What is left is one mark meaning "⏎ opens this", which never moves
  and stands down the moment the caret leaves the box — past that point `⏎`
  belongs to whatever Tab focused. `/` reaches the box from anywhere, the same
  key the graph page binds, so a reader who tabbed into the list and changed
  their mind does not have to tab back out of it.
* **Feature**: the 404's box escalates the way the graph page's does, through the
  **same component**. A bundle list cannot answer "where is the thing about
  decay?" — but the hub can, since `/search` reads inside every bundle it hosts.
  So a query matching no *bundle* drops the graph page's own bridge panel under
  the box — `No bundle matches "…"`, then `Search every bundle ⏎` and
  `Clear esc` — rather than saying no twice or inventing a second dialect of one
  idea two pages apart. The hits land under the list, each opening its concept in
  place (`/b/<slug>/?select=<id>`).
* **Fix**: the 404's guess only ever looked at the slug the router parsed, so it
  was silent on the commonest typo there is. `/bokf-tui/` is `/b/okf-tui/` minus
  one slash, and the router — which only looks *under* the mount — hands back no
  slug at all. The guess now falls back to the path's own first segment, whole
  first so a bundle really named `borders` beats `orders` reached by eating the
  mount letter. The dropped separator is named outright only on evidence with no
  second reading; short of that the page teaches the URL shape rather than
  guessing at the mistake.
* **Fix**: the graph's Filters panel had three chip groups and two grammars.
  Areas and tags were additive — nothing selected means everything, a click
  narrows, a second click undoes — while **types were subtractive**: every type
  showed until you clicked one *away*. Same chip component, same panel, opposite
  meaning, and the catalog's and tags' own type chips one view over were already
  additive, so the odd one out was odd twice. Types now select like everything
  else (`hiddenTypes` → `activeTypes`), which also means two types compound into
  a union the way two tags do — something the old model could not express at all.
  The change is a net deletion: `.chip.off` had no other user, and `chipRow`'s
  per-group state-class argument was there only to tell types apart from the
  rest. `typeFocused` collapses into the same shape as `tagFocused`, taking its
  one-type-bundle special case with it.
* **Change**: the `/b/` manager's registry forms are gone, and the page stayed.
  For a stretch both surfaces carried the same four verbs — the forms here and
  the graph page's ⚙ Bundles panel — which is two implementations of one
  contract and the shape that drifts. The panel wins because managing a set is
  something you do while reading it, not on a detour to a page you had to know
  existed. `/b/` keeps the jobs only it can do: the list, the redirect target
  when no bundle is named, the way back from a 404, and the empty state a hub
  with no bundles has no graph page to show. It now carries no forms, no script
  and no token — a page with nothing to post has no business holding the
  credential — and the four `POST /registry/<verb>` routes answer JSON to one
  caller instead of two shapes to two.
* **Note**: `--allow-manage` is now **`--read-only`**, and the axis flipped. The
  old flag read as the on switch and was not one — a loopback bind was already
  writable, and all `--allow-manage` did was widen that to a bind nobody should
  widen it to. So the opt-in is gone outright: a non-loopback bind is refused
  with no flag that opens it, because the registry is a per-user file and the
  machine that owns it is the machine that manages it. What is left is the way
  *out*, named for the word the hub's own refusal already used. A flag that
  cannot be misread as permission beats one that has to be read carefully.
* **Fix**: on a touch screen, tapping a concept destroyed the graph. At `≤768px`
  the inspector is `grid-template-columns:0 1fr`, so a tap measured `#stage` at
  **0 px wide** — the graph was not covered, it was gone, and exploring became
  open → read → close → tap the next dot. A **preview card** now rises at the
  bottom edge instead, carrying the concept's head over a graph that keeps every
  pixel and stays live; drag it up for the neighbourhood and the body, tap a row
  and it swaps in place while the camera walks. Two subtractions are the point:
  the 0.26 s entrance is gone outright — the card takes exactly one transform
  value for its whole life on screen — and a miss on bare canvas no longer
  dismisses it, because the misses are constant at that size and each one made
  the next dot replay the entrance. Together those two were the slideshow. The
  camera aims at the visible band rather than the canvas centre, or the selected
  node parks under the card describing it. The branch is wider than the chrome's
  (`≤768px` **or** `≤1024px` portrait): a portrait tablet has the same bug and
  wants the same gesture, while landscape at that size keeps the inspector.
  Folder and index taps fill the card too — they used to write into an invisible
  `#side-body`, so tree and cluster modes were silently dead on touch.
* **Note**: `clickNode` in the browser suite returned Cytoscape's collection
  from its `evaluate`, so Playwright deep-serialized the whole `cy` instance
  hanging off it — **5.0 s per tap**, against 6 ms with braces round the body.
  Eleven call sites across five specs; the full suite went 3.0m → 1.4m. The trap
  is that it never fails, only costs, so nothing points at it until a spec with
  three taps in it hits the 30 s timeout.
* **Feature**: the graph page stops hiding what it can do. The topbar box said
  "search concepts…", *filtered* the current view, emptied the graph in silence
  when nothing matched, and never mentioned the ⌘K palette that searches every
  bundle. It now carries the chord as a chip, a live `7/8` count — so an empty
  result is a number that reached zero rather than a view that went blank — and,
  on zero, a panel naming the bundle and the query with the way on: `⏎` hands
  the query to the palette prefilled and already searching. The escalation is
  the TUI's own, arriving four surfaces late. It will fire rarely, and that is
  the design working: the box's index reaches full bodies wherever the page
  holds them, so most real words match *something* locally.
* **Feature**: the registry moved onto the page. A ⚙ in the rail opens a
  **Bundles** slide-over — every registered bundle with its size, its health as
  a word, the default marked and the one being read marked differently, and a
  `⋯` per row carrying Make default, Rename… and Remove…. It reads a new
  `GET /bundles` (the [manager](capabilities/bundles-manager.md)'s own rows, as
  JSON) on every open rather than baking the list in, because the hub re-reads
  the registry per request and a boot snapshot goes stale silently. The four
  `POST` verbs gained a JSON rendering for it; every gate, status and sentence
  is unchanged, and asking for JSON is not a way around any of them. No **Add**:
  a browser cannot hand over a filesystem path, and registering is the agent's
  act — the footer says so rather than leaving the absence to be noticed.
* **Fix**: a slide-over parked at `translateX(100%)` **still occupies layout**,
  and `#views` did not clip — the Filters panel escapes this only because
  `#stage` does. The closed panel widened the document by its own 340px, and
  writing the spec found the half a prototype could not: it does the same *while
  sliding*, so fixing only the closed state still flashes a horizontal scrollbar
  on every open. `hidden` while closed plus `overflow:hidden` on `#views` settle
  both, and the spec samples `scrollWidth` across the whole animation — measured
  after it lands, the scrollbar has already gone. The hazard was latent for any
  panel added outside `#stage`, so the clip is the fix that matters.
* **Fix**: the hub's 404 was a centred card in a chrome that existed nowhere
  else in the product — the page a reader reaches by being wrong was also the
  page telling them they had left. It is now the app shell with nothing to show:
  the same rail, mark, theme toggle, topbar and row anatomy, plus the asked path
  as a chip, a did-you-mean, and a filterable list. The guess is Levenshtein
  with a shared-prefix shortcut, which is the part that earns its keep —
  truncation is the commonest way a slug comes out wrong, and plain edit distance
  scores `ord` three edits from `orders`. It is rendered in Ruby, not from an
  inlined payload: this is where someone lands when something has already gone
  wrong, and a page that needs JavaScript to say what happened has picked the
  worst possible moment to need it.
* **Note**: `--allow-edit` is now **`--allow-manage`**, with no alias — it had
  not shipped in a release. The flag is a permission grant, so the `allow-`
  prefix was right; the noun was wrong. Nothing edits anything: what it permits
  is adding, renaming, removing and re-defaulting *registry entries*, which are
  references, and "allow edit" invited the fear that a reader's markdown had
  become writable from a browser. The rename came with the test that was
  missing — a POST straight at a read-only hub, carrying a valid same-origin
  token, asserting 403 *and* a byte-identical registry file. It passed on the
  first run, which is the point: the guard was real and unproven, and unproven
  is how a guard quietly stops being real.
* **Note**: "workspace" is retired. It appeared only in the server layer and in
  this bundle, never in anything a user types — `registry` is the CLI verb
  family, `$OKF_HOME`, `OKF::Registry`; **Bundles** is what the surface has
  always called itself, in the TUI's view and in `/b/`'s own `<h1>`. It is also
  the only word true in both modes, since the hub serves ephemeral sets with no
  registry at all: a panel titled "Registry" would be lying half the time.
* **Feature**: the server reaches what the TUI reaches, through a browser. Three
  pieces, shipped in order. **Cross-bundle search**: the hub answers
  `GET /search?q=`, `Search.across` over every hosted bundle on one shared index,
  and the ⌘K palette gains a **Concepts** group that fetches as you type. The
  group comes last because it is the only one that arrives asynchronously, and a
  group landing above the cursor moves the row under the reader's fingers between
  the keystroke and the Enter. The engine is *named* `:index` rather than left to
  route off `fuzzy: true` — that worked only because nothing else declares the
  capability, and it is also the right engine here for a reason the CLI's default
  does not share: a long-lived server amortizes an index build over every
  keystroke, and the browser's own MiniSearch is a port of it, so a palette hit
  and an in-page search rank alike. **The [bundles
  manager](capabilities/bundles-manager.md)**: `/b/` went from a bare list to
  the browser counterpart of the TUI's bundles view — size, health verdict,
  default marker, and the entries the hub *cannot* host shown muted rather than
  omitted, because leaving them off answers "where did my bundle go?" with
  silence. **Registry writes**: four `POST` routes behind three gates
  (loopback-or-`--allow-manage`, a registry to write to, same-origin plus a
  per-boot token), each rebuilding the hub's served set from disk — a write that
  leaves the running server on the old set is a lie the next click believes.
* **Note**: the manager page carries no script, deliberately. Rename and Remove
  are `<details>` disclosures, Add is a text field for an absolute path — a
  browser cannot hand over a filesystem path at all (the File System Access API
  yields an opaque handle, and is Chromium-only), so there was never a picker to
  choose over typing. The first browser run of the new specs paid for itself: an
  HTML `pattern` whose character class is a valid Ruby regexp and invalid under
  the `v` flag a browser compiles it with, throwing on every keystroke where no
  integration assertion could see it.
* **Sync**: the browser suite now serves the page's CDN libraries from a local
  read-through cache, and [browser tests](design/browser-tests.md) records both
  what that buys and what it does not. It is keyed on the request URL rather
  than a manifest of the versions the template pins, because a manifest is a
  second copy of those pins that can drift into serving a library the page no
  longer loads — the one failure a cache is most likely to hide. A warm run
  touches no network (proven by making the fetch path throw and watching 64
  cases still pass), but `vendor/` is build output, so CI still starts cold and
  the `continue-on-error` rationale stands until the workflow restores it.
* **Correction**: the same note records that the cache does *not* make the suite
  faster, against the arithmetic that predicted it would. The premise — a fresh
  Playwright context per test re-paying ~330 ms of boot scripts across 400-odd
  cases — is wrong: Chromium reuses those subresources across contexts inside a
  worker's browser process. Controlled A/B at one worker, 28.7 s → 29.0 s; the
  suite is CPU-bound at ~500% across five workers. Recorded because full-suite
  wall clock is noisy enough (3.4 m, 3.6 m, 2.8 m on the same 412 cases) to
  invite reading the fastest run as a win, and because the discarded hypothesis
  is the part that would otherwise be re-derived from the per-request timings.

## 2026-07-20
* **Fix**: the graph no longer collapses on return from another view — and the
  cause was misdiagnosed for months. The [browser suite](design/browser-tests.md)
  held it open as a `test.fixme` on the theory it was a resize race (setView's rAF
  firing at 0×0, the ResizeObserver's 240ms debounce). Tracing it with the
  browser tools — trapping every zoom change, then `cy.animate`'s caller — showed
  the one animation that ran was a *fit*, not a resize: `fitGraph` reads the
  container's own width, and the one-shot boot fit (`setTimeout(fitGraph, 400)`
  after load) fires on whatever view is up by then. Leave the graph inside that
  window and it fits a hidden 0×0 canvas, `(w-2*pad)/bb.w` goes negative, and the
  zoom clamps to minZoom — staying there on return. Fixed by guarding `fitGraph`
  to skip a zero-size canvas (the template already guarded the `?view=` deep-link
  start for this exact reason, just not the navigate-away case). The `fixme` is
  now a normal `views.spec.js` test that fires the hidden fit by hand and asserts
  the zoom is untouched — deterministic in both modes, red before the guard, green
  after. The lesson: the old repro's load-sensitivity (deterministic alone, flaky
  under parallel workers) was not noise to route around with a `fixme` — it was
  the symptom of a timer racing boot. Under load, boot ran past 400ms and the fit
  landed while the graph was still visible, so it fit correctly and the bug
  "vanished." Reading the actual animation, not the plausible mechanism, found it.
* **Update**: `one-camera-move-per-click` (ed6c0af) is now covered — the #1
  uncovered regression fix, pushing [browser coverage](design/browser-tests.md)
  to ~50 of 94. It could not be closed with a cleverer test: every end-state
  observable (settled position, pan-event bursts, motion span) failed to tell the
  fix from a gutted `centerOn`, because the fix's contract is *when and how often*
  the pan commits, which the end state erases. So the page was made observable
  instead — a **product change**, deliberately the lightest kind (Tier 1): a
  test-only counter, `window.__camCenters`, bumped just before each committed
  centre-pan, invisible to users and there only to be read. The spec reads it at
  the one discriminating instant — synchronously right after the tap, before the
  260ms defer fires: 0 when the pan is correctly deferred, 1 when an immediate pan
  fired. Mutation-checked by flipping the defer off (`if(false)`), which turns
  that read 0→1 and reddens the test in both render modes. The honest shape of
  the closure, and the note it leaves: instrumentation earns its keep only when
  the contract is a sub-frame timing the end state cannot see.
* **Update**: [browser test coverage](design/browser-tests.md) climbed from ~10
  of the page's ~94 shipped-bug fixes to ~46, worked gap by gap down
  `test/browser/COVERAGE.md` — dim/highlight ordering, Indexes-only, link
  resolution, the file-tree collapse machine, the mobile chrome, two layout
  races, the untouched surfaces (palette, help, deep links, theme,
  catalog/tags/stats, splitters), the first-visit notes, the index layer
  (synthesized-vs-authored edges, ixVisibility), the fullscreen Mermaid diagram
  viewer, and — pushed to ~49 of 94 — the command palette's hub bundle-switcher
  (reached through a two-bundle server the config boots) and the ? sheet's focus
  management, plus the ⌘⏎ new-tab chord a bundle row honours (window.open, not a
  same-tab nav), the Mermaid re-theme that re-renders an inline diagram on a
  theme toggle, and the `prefers-color-scheme` boot fallback. The graph-collapse
  known bug is now a `test.fixme`, not a `test.fail`: its race reproduces
  deterministically run alone but is load-sensitive under the full suite's
  parallel workers, so a `test.fail` flipped to an intermittent *unexpected pass*
  — a coin-flip red that trains the reader to ignore the very signal it raises.
  `fixme` keeps the bug on the record and the suite deterministically green.
  Every new spec was mutation-checked against the
  code it covers. Two dividends: the work found that selecting a node in cluster
  mode faded the whole graph (a compound parent's opacity cascades to its nodes)
  — reproduced red, **fixed**, pinned by `effectiveOpacity`; and that a log's
  "Open in graph" button stayed visible though the code hides it, because
  `.btn.text{display:inline-flex}` outranked `.btn[hidden]` at equal specificity
  — **fixed** with a `.btn.text[hidden]` rule, the precedent already used for
  `.fp-head`. The camera fix `one-camera-move-per-click` was left uncovered here
  on purpose — the panel-open `cy.resize()` re-centres the graph last, so the
  node settles identically with the pan removed, and a settled-state test would
  green with the fix deleted (the lesson this log keeps relearning: a test that
  cannot fail is worse than none). It was closed in a later pass, but only by a
  product change; see below.
* **Addition**: [browser tests](design/browser-tests.md) — the graph page is now
  driven in real Chromium, every spec in both render modes, with any thrown error
  failing the run. Two findings worth more than the suite itself. The page has a
  real bug: dwell ~300ms on another view, return to Graph, and the graph redraws
  at a tenth of its size; both resize paths run and neither is sufficient. And
  the first version of the test for it **could not fail** — it read `cy.width()`,
  which reports the live container while the render is collapsed, so it passed
  with every resize path deleted. A test that cannot fail is worse than none,
  because it is counted; mutation-check a new spec or it is not proven.
* **Correction**: [server trust boundary](design/server-trust-boundary.md)
  claimed both XSS paths were closed. They were *implemented*, but nothing
  asserted either: the tests checked that the string `DOMPurify` appears and that
  it is a function at boot, both of which a render path skipping the sanitizer
  passes. Measuring the browser suite against the page's own 44-commit history —
  ~230 behaviors, ~94 of them fixes for bugs that really shipped — is what
  surfaced it. The lesson repeats the overview.md one below at a different
  altitude: a claim nobody checks drifts from the code, and "we sanitize" is a
  claim, not a test.
* **Update**: both guards are now asserted, against a hostile fixture bundle
  whose payloads set flags on `window` — so the test says *the script did not
  run*, not *the markup looks clean*. Each was mutation-checked. The one worth
  remembering: with the sanitizer removed, the `<script>` payload did **not**
  fire, because `innerHTML` does not execute script tags; only `<img onerror>`
  did. A fixture of script tags alone would have gone green against a page with
  no sanitizer at all — the security-test version of the same trap as the
  `cy.width()` test above, where the assertion was incapable of failing.
* **Correction**: a sweep for stale prose before merge, and the two that mattered
  had **nothing to do with this branch**. `overview.md` still said "exactly two
  runtime dependencies" — `minifts` made it three at 1.9.0, and this log records
  fixing that same count in other files *twice* while overview.md was missed both
  times. Its read-view list was also missing `types`. A count stated in five
  places drifts in the one nobody edits; the lesson is to grep the claim rather
  than fix the instance, which is exactly what the two earlier entries failed to
  do.
* **Correction**: `cli.md` grouped the verbs into "three groups" — a harmless
  editorial arrangement when the map was a heredoc, and **wrong the moment
  `.group` became something a command declares**. `CLI::GROUPS` has five built-in
  groups plus `:extension`, and the table put `graph` under Read and `registry`
  under Act when both return their own. The table matches the code now. A doc can
  go stale by the code growing a real version of what the doc was approximating.
* **Change**: the prefix rule's own [design note](design/extension-points.md)
  described itself, in its `description:` frontmatter, as loading only `okf-*`
  gems *"because requiring one runs its code"* — the trust-first framing the body
  spent two commits retiring. Third instance of the same reframe, found the same
  way: fixing the sentence in front of you rather than searching for its copies.
  The description is what `search` and `index` surface, so it was the one most
  read and the last corrected.
* **Correction**: the fail-open fixed yesterday **survived one frame above the
  fix**. `plugin_gem_name` learned to refuse a name it could not read; the
  `rescue ::StandardError` in `plugin_paths` still answered `[]` and threw its
  exception away, so `Gem.find_latest_files` raising turned every installed
  extension off in total silence — indistinguishable from a machine with none.
  That is the same defect, in the same file, closed one layer too low: the fix
  was aimed at the frame the bug was *found* in rather than at the shape of the
  bug. The search failing is reported on its own terms now, since there is no
  discovered path to hang a refusal on. Three failure modes, each closed
  separately; the entry below claimed the second was the last of them.
* **Correction**: the entry below asserts *"one pass has one outcome, so the
  lookup either answers for every path or fails for every path"* — and the code
  it describes **did not do that**. `@gem_index ||=` caches a value, not an
  outcome, so a raising enumeration ran again for every discovered path (three
  paths, three passes, counted). A failure clearing between paths — a gemspec
  rewritten by a concurrent `gem install` — would refuse one and trust the next
  in the same run: the very lottery the entry says was eliminated, still open in
  the one branch the change existed for. The failure memoizes with the result
  now, and a test counts the passes rather than trusting the sentence.
  Second time in two days a comment stated a mechanism from intent rather than
  from reading the code, both times in prose about *why* — the part no test
  covers, and so the part that needs the evidence gathered *first*.
* **Change**: the prefix test reads as a named question — `trusted_gem?`, with
  `nil` (belongs to no gem, trusted) and `UNKNOWN_GEM` (lookup failed, refused)
  as written branches. It was `name.is_a?(::String) && name.start_with?(…)`,
  which excluded the sentinel by type-testing around it and needed four lines of
  comment to say what one line now says. The type test also mis-stated its own
  stakes: dropping it would not have raised NoMethodError *instead of refusing*,
  it would have raised inside `plugin_paths`' own rescue and returned `[]`.
* **Note**: the `gem_index` comment sold the change as a saving. It is not one —
  it replaced a `find` that short-circuits on the first match with a `map` over
  all 282 specs (1.0 ms), so on the ordinary one-path discovery it is strictly
  more work. The failure-shape argument was always the real one and now stands
  alone.

## 2026-07-19
* **Correction**: the Note below justified its own change with a **mechanism
  that does not exist**. It said a second `folder.graph` call would leave "every
  concept therefore parsed twice"; concepts are parsed once, at `Folder.load`,
  and `Graph.build`'s first line reads `bundle.concepts` from memory — no
  `File`, no `Dir` on that path. What the second call actually costs is a second
  *graph build*. The change was right and stands; the reason given for it was
  invented rather than read, which is the same failure the testing rule names
  (*"never assert what you assume the code does"*) committed in a comment, where
  no test can catch it. Corrected in both `lib/okf/cli/render.rb` and the Note.
* **Correction**: the fail-closed rule the entry below records **refused without
  saying why**. `plugin_gem_name` rescued the lookup and threw the exception
  away, so a machine with one corrupt gemspec lost *every* installed extension
  under "its owning gem could not be determined" — a message naming no gem to
  fix and no reason to look. The cause is carried now and printed with the
  refusal. Fixing fail-open by fail-closed only pays if the closed door says
  what shut it; the first version traded a silent wrong answer for an
  undiagnosable right one.
* **Change**: the owning-gem lookup walks the installed specs **once per
  discovery** rather than once per discovered path (`gem_index`, built lazily so
  the ordinary run — nothing discovered — still never walks them). The saving is
  small and was never the point: one pass has one outcome, so the lookup either
  answers for every path or fails for every path. Per-path enumeration made that
  a lottery, where a path matching an early spec could succeed while a later path
  tripped over the corrupt one — a rule holding for some extensions and not
  others, which is worse than either.
* **Correction**: `reset_plugins!` grew a guard — `unless @builtins.nil?` —
  against being called before `seal_builtins!`, and the guard was **wrong twice
  over**. The state cannot occur (`seal_builtins!` runs at the bottom of
  `cli.rb`, so anything able to name the method has already loaded it), and had
  it occurred the guard would not have caught it: `builtins` is
  `(@builtins ||= []).dup.freeze`, so reading it once — `extension?` does — flips
  the ivar from nil to `[]` and the guard passes, permitting exactly the empty
  registry its own comment called the thing to avoid. Removed rather than
  repaired: a guard against an unreachable state is speculative, and one that
  reads a memoizing accessor to decide whether the memo has been set is a bug
  waiting for a caller.
* **Correction**: the correction below **fixed one comment and claimed the
  file**. `lib/okf/cli.rb` carried the retired trust-first framing in *two*
  places — on `plugin_paths` and, twelve lines above it, on the
  `PLUGIN_GEM_PREFIX` constant itself, which still asserted that the prefix
  "closes the case where the user chose nothing: a transitive dependency
  shipping this file is discovered and skipped rather than run" — the exact
  claim retired as nearly empty. The entry below says the code was "reframed
  there too", and that was true of one comment out of two. Both read the
  convention way now, with the constant carrying the short version and pointing
  at `plugin_paths` for the argument, so there is one place to keep right rather
  than two to keep agreeing. The lesson is sharper than the one below it and
  aimed at the fix rather than the drift: **shown one instance, I fixed that
  instance instead of grepping for the class.** The command that would have
  caught it is the same command the entry below prescribes — `grep -rn trust
  lib/` — and I wrote that prescription without running it.
* **Change**: `okf skill <a> <b>` **installed into `<a>`, ignored `<b>` and
  exited 0.** Every `<dir>` verb refuses a trailing argument through
  `positional_dir`, but `skill` takes a *destination*, not a bundle, so it read
  as outside the rule and hand-rolled its own `argv.shift` — the one verb with a
  positional that never met the guard. It goes through the shared `positional` +
  `no_extras?` pair now and exits 2 before writing anything, and [cli](cli.md)'s
  exit-code section states the rule as being about the **positional** rather
  than about a second *bundle*, since the narrow phrasing is what made the verb
  look exempt. Predates the registry work — a straight carry-over from the
  monolith, found by reviewing the moved code rather than the diff.
* **Correction**: the `okf-*` rule **failed open**, which is the interesting half
  of a rule everyone had agreed earns little. `plugin_gem_name` rescued to `nil`,
  and `nil` is also the answer meaning "belongs to no gem" — the deliberately
  *trusted* case for a checkout or a `ruby -I` path. So one corrupt gemspec
  anywhere on the machine (`Gem::Specification` enumerates every installed spec)
  would make the lookup raise, every discovered path come back "belongs to no
  gem", and every plugin load — with no refusal printed, because nothing was
  recorded as refused. A failure to determine is now its own answer, refused and
  reported. Recorded in [extension-points](design/extension-points.md), since it
  is a claim about the rule holding *under failure* rather than in the happy
  path, and those are different claims that read like one.
* **Note**: `okf render` built the graph **twice** — once inside
  `Render::Graph.static` to bake the page, once more purely to count nodes for
  the "wrote N concepts" line. `Graph.build` maps one node per concept, so
  `folder.bundle.concepts.size` is the identical number off an object already in
  hand. The count is unchanged (25 on this bundle, matching `okf graph`).
  `server` still does this in both its modes and says so in a comment; left
  alone deliberately, as its own change.
* **Correction**: the reframe below stopped at the docs and left the **code
  comment** behind. `plugin_paths` in
  [`lib/okf/cli.rb`](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli.rb)
  still opened "Narrowed to gems named `okf-*`, which is a **trust** decision
  rather than a tidiness one" — the exact framing the commit below retired, in
  the file that concept's own citation points at. So the bundle, `AGENTS.md` and
  the changelog said convention-first while the code said trust-first, and the
  citation carried a reader from one to the other. Reframed there too: the
  convention leads, the guard is named as mild, and the rule underneath that
  *is* load-bearing points at `plugin_gem_name`. The lesson is one this bundle
  keeps meeting from new angles — **"the code does not change" is true of
  behaviour and false of prose.** A comment is prose the tools cannot see:
  `validate` and `lint` both called the bundle healthy, correctly, because the
  drift was outside it, and a docs-only pass has no failing test to stop it. A
  grep for `trust` over `lib/` would have found it in one command, which is the
  same shape as the `--engine` drift recorded further down: instantly findable
  *if* you think to look outside the bundle for the sentence you just changed
  inside it.
* **Note**: the `security` tag **stays** on
  [extension-points](design/extension-points.md), a judgment the reframe invites
  and does not settle. The concept still argues where the trust boundary sits,
  why the pure-Ruby escalation is real but narrow, and why an `$OKF_HOME`
  allowlist was refused — that is security reasoning whatever it concludes, and
  someone auditing this gem's code-execution surface should reach it. A tag that
  marks *"this reasons about trust"* is not falsified by deciding that one rule
  inside it earns little; dropping it would hide the concept that explains why
  the prefix is not a defence from exactly the reader who needs that.
* **Correction**: a maintain pass over the CLI restructure found three citations
  pointing at code that had moved, each reading perfectly and each now wrong:
  [graph-server](capabilities/graph-server.md) cited `lib/okf/cli.rb` for the
  `serve` boot seam and [render](capabilities/render.md) for the `render` verb —
  both now live under `lib/okf/cli/` — and
  [integration-first](design/integration-first.md) still called low coverage "in
  `cli.rb`" a hole, when `cli.rb` is now a dispatcher and the verbs it meant are
  in `cli/`. `validate` and `lint` called the bundle healthy throughout: a
  citation that names a real file nobody moved *to* is invisible to both.
* **Update**: the **shipped skill** learned that the verb list is open. Its
  [cli reference](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/reference/cli.md)
  and `SKILL.md`'s verb row now say an installed extension adds verbs of its
  own, so a verb `okf help` shows and the reference does not document reads as
  **normal rather than a documentation error**. Worth doing because the skill is
  how an agent learns this surface, and an agent that treats an unknown verb as
  a doc bug will go looking for the bug. `rake plugin:sync` run, so the
  generated copy does not drift.
* **Update**: `cli_plugin_test.rb` added to
  [integration-first](design/integration-first.md)'s tree, which is an
  enumeration and therefore the one thing grep cannot audit. It is the odd file
  there — it names no bundle and tests no verb of ours — so the entry says why.
* **Note**: tag curation merged the singleton `plugins` into **`extensibility`**,
  which was already carried by [search-engines](design/search-engines.md). Two
  singletons naming one theme, on the two concepts that are about that theme and
  link to each other; `extensibility` was established first, so the newer name
  merged into it rather than the reverse. Singletons 9 → 7.
* **Change**: the CLI became a **registry**, and with it an extension point — the new [extension points](design/extension-points.md) concept, with [cli](cli.md)'s dispatch section rewritten around it. `lib/okf/cli.rb` was 1,794 lines and a 15-arm `case`; the verbs now live one per file under `lib/okf/cli/`, each a `Command` subclass registering itself at load, with the shared surface (refs, flags, the JSON emitters, the printers) on a base class. Behaviour is unchanged and the suite says so: every existing test passed untouched. Any gem shipping `okf/plugin.rb` on its load path can now add a verb — `okf-tui` is the first, answering `okf tui` — with **no edit to this gem and no list of known addons**, which a test enforces by grepping `cli.rb` for their names. `Search.register` set the idiom and this copies it exactly: append-only, idempotent by id, duck type checked at registration, so an addon cannot displace a built-in.
* **Note**: discovery is **lazy**, and the arithmetic is the one that made the scan the default engine. `Gem.find_latest_files` costs ~11ms on the 2.4 floor — small, and still not worth paying on a run that only wanted `okf lint`, so a built-in resolves and dispatches without scanning at all. Only an unknown verb and `okf help` pay. An unplanned consequence, worth keeping: an addon claiming a built-in's verb is not merely refused, it is never loaded, because running that verb never triggers the scan.
* **Note**: discovery is a **code-execution** decision, so the trust boundary is
  argued in [extension-points](design/extension-points.md) rather than assumed.
  The usual principle — Ruby trusts `gem install`, not `require` — is not the
  whole truth: it holds for native extensions, which run `extconf.rb` at install,
  and **not** for pure-Ruby gems, which execute nothing until something requires
  them. So a convention loader does escalate, narrowly, for a pure-Ruby gem that
  is installed but never required. Bounded two ways: under Bundler the scan is
  bundle-scoped (the Gemfile is already an allowlist, measured — a sibling
  okf-tui checkout absent from the Gemfile is not found), and only `okf-*` gems
  are loaded, so a transitive dependency shipping `okf/plugin.rb` is discovered,
  skipped and reported. Resolving the owning gem's name reads `full_gem_path`
  and never loads the file; a test pins that. An `$OKF_HOME` allowlist was
  **considered and rejected as disproportionate** — the window it closes is one
  the user opened with `gem install`, and it would cost the property that makes
  the seam worth having.
* **Correction**: the `okf-*` rule was first written up as a **trust decision**,
  and that oversells it. Pressed on whether it earns its place, the honest
  reading is that the window it closes is nearly empty: a transitive dependency
  is required by its parent in normal use, so `require "foo"` already runs
  `foo`'s dependencies — what is left is a gem installed and then used by
  nothing at all. As a security control it earns very little, and calling it a
  defence invites the false confidence that is worse than no rule. It stays on
  its own merits, as the **naming convention** Jekyll and Vagrant use: it makes
  what counts as an okf extension explicit and stops an unrelated gem claiming
  the `okf/plugin.rb` path. Cost measured at 0.0ms per discovered path; the cost
  that is real falls on authors, who must name an extension `okf-` something.
  Reframed in [extension-points](design/extension-points.md), the changelog and
  `AGENTS.md`. The one rule underneath that *is* load-bearing and keeps its
  weight: naming a gem must never load it.
* **Note**: **Thor was rejected, and the floor decided it** — Thor 1.3+ requires Ruby >= 2.6 against this gem's [2.4](design/ruby-floor.md), and only the EOL 1.2.2 accepts it, which is the pin-an-old-line-for-everyone mistake already recorded. It would also be a fourth [runtime dependency](design/runtime-dependencies.md) buying little: what was needed was a registry, not an option-parsing DSL, and `optparse` plus this gem's help/exit-code/stream-injection contract were already in hand. What kamal's Thor layout *did* supply is structure — a base class holding the shared surface, one file per command, privacy as the command boundary. Ideas are free.
* **Correction**: the plugin test seam was **wrong in a way only a real gem could show**. `reset_plugins!` cleared the registry but left the file in `$LOADED_FEATURES`, and `require` is idempotent — so the next scan found the plugin, required it, got `false`, and registered nothing; the verb was gone until the process restarted. Every test hid it by writing its plugin to a fresh `Dir.mktmpdir`, so the path differed on every load and `require` always ran. It surfaced the moment the seam was pointed at `okf-tui`, whose `lib/` path does not move. The lesson is narrower than "test with real things" and worth stating: **a fixture that varies where the real thing is fixed can hide a bug in exactly the dimension it varies.**
* **Correction**: [search](capabilities/search.md) listed **prefix matching** among what the index buys, and it buys nothing. A substring match already reaches every prefix — `dedup` finds `deduplication` under either engine, while `duplication` and `uplicat` find it under the scan alone — so `prefix` is what a token index needs to *catch up* to raw text, not a capability it adds on top. The claim was written the same day the scan became the default, into the very section arguing when to reach for the index, and it survived because "prefix matching" reads like a feature the alternative lacks. It was caught only by building the [skill](capabilities/agent-skill.md)'s engine-selection table and running each row instead of restating it: a table forces a claim per cell, and a cell is small enough to test. The advantages are now stated as a closed list of **three** — relevance ranking, typo tolerance, page parity — because a numbered list resists growing by plausible-sounding items in a way an open one does not.
* **Correction**: a maintain pass over the engine swap found three concepts the change falsified without touching, each a sentence that still reads perfectly. [The graph server](capabilities/graph-server.md) carried the worst of them: it told the story of a gap *closing* — "the browser and the CLI's search used to diverge here… that gap is now **closed from the other side**: the CLI runs the same engine" — and the swap reopened it that same day. It says so now, and says why it is deliberate rather than a regression: a page holds its index across every keystroke while a CLI process builds, asks once and exits, so the two surfaces have different lifecycles and `--engine index` is the setting where they agree. [Runtime dependencies](design/runtime-dependencies.md) had the subtler one — `minifts` is still justified (`--fuzzy` has no other implementation, BM25+ no other source, page parity no other route) but it now backs a **non-default** engine, and the argument that admitted it was *ranked search by default*. A dependency whose warrant weakened should say so rather than keep quoting the warrant. The [design index](design/index.md) summarized the engine contract as "chosen by capability" one release after `--engine` and one day after the scan took the default.
* **Change**: the default search engine became the **scan**, and the index became opt-in (`--engine index`, or `--fuzzy`, which routes there). [search](capabilities/search.md) and [the engine contract](design/search-engines.md) both invert around it. The argument is a lifecycle one the earlier benchmark had already named but not acted on: a CLI process builds an index, asks one question and exits, so the build amortizes over nothing — measured end to end, **3.00 s against 0.24 s at 1,000 concepts**, 0.83 s against 0.18 s at 250, with the build ~95% of the index path at every size. Recall settled it rather than speed: raw-text matching has no tokenizer, so it has none of the tokenizer's holes, and the code-span loss recorded below stops being something a plain `okf search` pays. What the index buys — BM25+ ranking, prefix matching, `--fuzzy`, and rank parity with the browser page — is now reached by asking for it, which makes that parity **conditional** where the constraint in `AGENTS.md` had stated it flatly. The change costs one constant: capability routing already picks the first available engine offering what the query requires, so `--fuzzy` finds the index by itself and `-e` stops moving anything, since the default now offers `:regexp` outright.
* **Correction**: [the engine contract](design/search-engines.md) still read "there is deliberately **no `--engine` flag**", a decision reversed by the release below it — the concept recorded the reasoning for capability-only routing and never recorded its reversal. It says both things now, because the *why* is the durable part: a capability flag can only express what a query needs, and a matching *model* requires nothing, so under capability routing alone the non-default engine was unreachable at any price. The drift is the kind the [enumeration blind spot](capabilities/read-views.md) does not cover and a grep for `--engine` finds instantly *if* you think to run it: the doc named the flag in order to deny it, so it matched every search for the thing it was wrong about.
* **Correction**: `accepted_losses_test.rb` and `recall_test.rb` both measured the index **through the default engine**, so the day the default moved they would have gone green while testing nothing. Each now names `--engine index` explicitly, and the rule is worth stating: a test that provokes a named engine's behaviour must name it, or it is really a test of whatever the default happens to be. `recall_test.rb` also gained the mirror assertion — the default has *no* recall holes — because the property the swap was for deserves to fail loudly if it is ever given back.

## 2026-07-18
* **Change**: `okf search` gained **`--engine NAME`**, and with it the answer to a question the capability flags structurally could not ask. A flag routes by what a query *requires* — `-e` needs `:regexp`, `--fuzzy` needs `:fuzzy` — but raw-text matching requires nothing, so nothing selected it. `--engine scan` names it directly: pre-index behaviour, phrases and infixes and dotted identifiers and code spans all matching, paying the coarser ranking for it. The design decision underneath is that the engine chooses **where** to match (tokens or raw text) and `-e` chooses **how** (literal or pattern) — previously the scan compiled every term as a regexp, invisible while `-e` was its only door, but wrong the moment `--engine scan` opened another: `7.2.0` would have matched `7x2y0` and `review (pending` would have been exit 2. Terms are escaped now unless `--regexp` says otherwise. A named engine that cannot do what was also asked is refused rather than falling back — falling back answers a different question than the one posed — and the refusal names an engine that can. This also makes the capability router's error path reachable from the CLI for the first time; it was previously dead code awaiting an addon.
* **Correction**: [search](capabilities/search.md) missed the **largest** recall loss of the index swap. A backtick is Unicode `Sk`, not `\p{P}`, so MiniSearch's tokenizer never splits it off and a word inside a code span indexes as one glued token: `` `minifts` `` is not found by the query `minifts`. In this bundle that is **409 distinct tokens over 1,013 occurrences**, and `okf search .okf minifts` answers 2 where the scan answers 5. The original swap notes recorded exactly one loss — the infix `ustomer` — because the analysis reasoned about the tokenizer instead of running queries against the corpus. The lesson generalizes past this bug: the conformance suite asserts that engines agree with each other *structurally* and cannot detect that both are missing a third of the matches. The tests that found real defects here — the losses pinning, the tokenizer spike — were the ones that ran real queries against real content.
* **Change**: search became a facade over **N engines** chosen by capability, replacing the `regexp ? scan : index` ternary that could not hold a third. [The engine contract](design/search-engines.md) is the new concept: the facade owns everything that defines a result (documents, the row and its key order, the snippet, the sort), and an engine answers only which documents match, how well, and where. Selection is by what the query *needs* — `-e` requires `:regexp`, `--fuzzy` requires `:fuzzy` — so there is no `--engine` flag and no second vocabulary to keep consistent with the first. Routing is silent by decision: no note, no header change, no JSON key, because someone who typed `-e` does not need to be told what `-e` does on every run. The consequence is that `okf search --help` became load-bearing rather than decorative — it is now the only surface where the scan's existence is discoverable — and an integration test pins both the attribution and the silence, since a well-meaning `note: using the scan engine` is exactly the kind of thing that drifts back in.
* **Correction**: [search](capabilities/search.md) claimed ranking contained the precision loss — "in every probe the true hit ranked first", so the cost was only extra rows below the answer. **It is false.** Writing the tests that pin the loss produced the counterexample immediately: BM25 normalizes by field length, so a short body dense in `7`, `2` and `0` outscores the concept that actually says `7.2.0`. This bundle proves it on itself — `okf search .okf 7.2.0` ranks [the Ruby floor](design/ruby-floor.md), a page full of `2.4` and `3.x`, **above** [the graph server](capabilities/graph-server.md), the one concept naming the version. The original claim came from probes on this bundle read too kindly; the number was never checked against a fixture built to break it. The mitigation is partial, not total, which upgrades `-e` from a nicety to the reason the tradeoff is acceptable at all.
* **Correction**: the [design index](design/index.md) still described the runtime dependencies as "exactly `rack` and `webrick`" a release after `minifts` made them three. The [dependency concept](design/runtime-dependencies.md) itself was updated at the time; its one-line summary in the area index was not, which is the enumeration drift a grep can never find — you cannot search for the word that should be there and isn't.
* **Correction**: the oracle rule the roadmap carried for addon search — backends must return "the same match set, modulo ranking order" as the kernel — is retired. It was a rule about one implementation wearing two hats, and the moment two engines legitimately disagree (a phrase, an infix, a dotted identifier) it makes one of them a bug by definition. Replaced by a shared **conformance suite**: what every engine must do regardless of engine, plus capability-gated blocks for what only some can. A registered engine with no conformance class is a failing test.
* **Sync**: the CLI's search stopped being a linear scan and became a full-text index, so the browser and the CLI now run **one engine**. [`minifts`](design/runtime-dependencies.md) — the pure-Ruby port of the MiniSearch build the page already loads — is the gem's third runtime dependency, admitted because it costs the footprint nothing the first two were chosen to protect: no native extension, no dependency subtree, the same Ruby 2.4 floor (verified on 2.4.10), and it is precisely what defers SQLite + FTS5. [search](capabilities/search.md) records what changed underneath: terms are **tokens** matched whole or by prefix rather than substrings, ranking is BM25+ with the old field weights riding as boost, `--fuzzy` opts into the browser's typo tolerance, and `-e` stays a linear scan because a pattern is the one query an inverted index cannot answer — so `-e --fuzzy` is a usage error rather than a silently dropped flag. The row still carries which fields hit, read off the index's own per-term record: ranking improved and nothing was traded for it. The [gap the sync below opened](capabilities/graph-server.md) — CLI substring versus browser fuzzy — is closed from the CLI side, one release after it was named.
* **Correction**: the cross-bundle merge's justification died in the swap, silently. [search](capabilities/search.md) had argued that merging rankings was "legitimate because scores are absolute term weights, **not per-bundle normalized**" — and BM25 is nothing *but* per-corpus normalization, weighing every term by how rare it is. Searching each bundle separately and interleaving the results would have produced a list that looked sorted and compared nothing, with no error, no failing test, and no visible symptom beyond rows in a slightly wrong order. The fix is structural rather than a caveat: the searched bundles are indexed as **one corpus**, so the ranking is comparable by construction, and the observable proof is now a test — the same concept scores *lower* merged than alone, because the term got commoner. The lesson generalizes past this bug: a claim can be load-bearing for code it never names. That sentence was the merge's whole warrant, it lived in a *capability* doc while the change was to an *engine*, and swapping the engine falsified the warrant without touching the merge.
* **Correction**: the benchmark that motivated the swap measured the wrong lifecycle, and the bundle now says so where a maintainer will meet it. `minifts` sustains ~44–56× the scan's query throughput — true, and the right number for a browser or a server holding an index across many queries. `okf search` is a process that builds an index, asks **one** question, and exits, so it pays the build and amortizes it over nothing: 55 ms against the scan's 2.4 ms on this bundle, 2.2 s against 103 ms at a thousand concepts. Invisible at the size real bundles are today, a 20× regression at scale. Recorded in [search](capabilities/search.md) as the current ceiling with the cached prebuilt index named as what collects the throughput, because the honest version of "we made search 50× faster" is that we made it 50× faster *per query* and the CLI does not yet run enough queries to notice. A benchmark's unit of work has to match the caller's lifecycle, or it measures something real that nobody experiences.
* **Correction**: [runtime-dependencies](design/runtime-dependencies.md) was titled "Exactly two runtime dependencies", and said two in its title, its description, *and* its body table — three copies of a count that a third `add_dependency` line made wrong at once. It was flagged as holding in the pass below, correctly, because that pass added a CDN asset rather than a gem; this one added the gem. The enumeration lesson the bundle keeps re-learning has a corollary worth writing down: a concept that survives one review because the change fell outside it is not thereby durable, and the *count in the title* is the copy most likely to be missed, since it reads as a name rather than as data.
* **Correction**: the sync below documented the new search everywhere it was a *feature* and missed the one place it is a *liability*. The [trust boundary](design/server-trust-boundary.md) closes with what sanitizing does not cover, and that paragraph **enumerates the third-party code the page runs** — "Cytoscape, marked, and DOMPurify from a CDN" — so adding a lazily-loaded MiniSearch made a security constraint quietly incomplete without touching a word of it. Rewritten to name the boot set and the lazy set (Mermaid, Panzoom, the layout engines, MiniSearch) and to say what they cost: each is trust extended to the CDN as much as to the bundle, with MiniSearch pinned to an exact `7.2.0` because it has to *agree* with the Ruby port rather than merely work. [runtime-dependencies](design/runtime-dependencies.md) was checked in the same pass and holds — a CDN asset is not a gem dependency, and "no build step, no JavaScript toolchain" is still true — so its date moved and its body did not. The lesson is an enumeration one the bundle keeps re-learning from new angles: searching for the *feature* finds the concepts that describe it, and none of the concepts that merely **list** what it joined. The query that found this was `dependency` and `CDN` — the asset class, not the feature name.
* **Sync**: the graph page's search box became a full-text index, and the interaction bugs it exposed were fixed. [MiniSearch](capabilities/graph-server.md) — lazy-loaded, pinned to the `7.2.0` build the Ruby `minisearch` port tracks so a Ruby-built index and the browser's rank identically — now backs the graph, catalog, files and Indexes views: ranked, multi-term, prefix and typo-tolerant over title, id, type, tags and *description*, plus bodies wherever the page already holds them, which is why [`okf render`](capabilities/render.md)'s baked file searches bodies offline while the live server's index stays metadata-only until a backend body index exists. The graph could not be searched by a leaf's description at all before. It also splits the bundle's search story in two on purpose, which [search](capabilities/search.md) now records: the CLI stays deterministic substring so a row can say which field hit, the browser goes fuzzy because a human scanning a graph wants the near miss, and the shared build is the road back to one engine. The bugs were all *filter-shaped*. Cluster mode draws a box per area and never re-applied the active filter when you clustered, so entering cluster mode with a search on left phantom empty rectangles — and the tell was that type and tag filters, which are applied *while already clustered*, never did it. The file tree force-expanded every folder whenever a search was active, so its fold clicks were dead. And a dense graph leaves almost no empty canvas to click, so deselecting got a key. The lesson is what the phantom boxes taught: the filter pass was correct, and provable — the defect lived in the *other order*, where clustering built the boxes after the filter had already run, and only one of the two orders had ever been exercised.
* **Sync**: the graph renderer moved out of the server, and five concepts caught up. `OKF::Server::Graph` became [`OKF::Render::Graph`](capabilities/render.md) — the view layer paired with the pure [graph model](model/graph.md) — and the static bake left the Rack app: what was `App#render_static` is now `Render::Graph.static`/`.payload`, so [`okf render`](capabilities/render.md) no longer instantiates a server to write a file. The [graph server](capabilities/graph-server.md) keeps only the HTTP concern, its `GET /` delegating to the renderer, and both draw from one [`OKF::Bundle::Folder`](capabilities/library-api.md) — the `log_entries` builder moved there too — so the baked payload and the live endpoints derive from the same source and cannot drift. The drift the move left behind was pure address-rot: [render](capabilities/render.md)'s `resource` and citation, the [trust boundary](design/server-trust-boundary.md)'s template path, the [library API](capabilities/library-api.md)'s `render_static` surface, the graph server's own citation still crediting the app with a method it no longer holds, and the [core/shell split](design/core-shell-split.md)'s shell diagram, which had no renderer node though `boundary_test`'s denylist had reserved `Render::` all along. Behavior did not change — the render output is byte-identical, which is why nothing mechanical could have caught this: a moved file leaves every sentence reading true while its citations point where the code used to be.

## 2026-07-17
* **Correction**: the [graph server](capabilities/graph-server.md) still called its `Cmd/Ctrl-K` palette a hub-only affordance — "the switcher exists only where switching is possible… the affordance never appears" — a sentence the palette rework made false without touching the file: the palette now opens in every mode, views always in the list and bundles only where a hub serves siblings, which is what the template's own comment records. The section was renamed for what it describes now (one palette, every mode) and gained the keyboard half the concept never had: `/` to the current view's search, `?` for the shortcut sheet written against the key handler it documents. Caught while consuming the concept to write release copy — the decay sweep skipped the server nodes as "reviewed this week," and this is the counterexample worth keeping: *reviewed* dates from when the review ran, not from when the last commit landed, and a node can drift in the gap between the two.
* **Correction**: a decay sweep of the non-CLI half — every concept in `format/`, `model/`, and `design/`, plus the judge and library capabilities, re-read against the code it documents — turned up four drifts no tool can see. The [linter](capabilities/linter.md) had grown a seventeenth check while its prose still counted sixteen, a number its own table already contradicted by listing all seventeen ids. The [validator](capabilities/validator.md)'s §9.1 described only frontmatter that will not *parse*, but a file that will not *open* fails it now too, reported from `bundle.unparseable` with its errno — a change that landed after the concept's last sync. The [concept](model/concept.md) model's whole "the id follows the path" thesis predated the explicit-frontmatter-`id` override the gem's link resolution is now built around, and `#links` was labelled bundle-relative when it returns every raw target with `#external_links` the subset. And [ruby-floor](design/ruby-floor.md) still showed the old read-write Docker truth-test, not the read-only copy-and-drop-the-lockfile form the maintainer guide now carries. [library-api](capabilities/library-api.md) gained the `render_static` surface beside `App.new`. The rest — the format layer, the [bundle](model/bundle.md) and graph models, the dependency and Ruby-floor constraints — verified accurate against the current code and had their timestamps refreshed to say so: a re-verified date is knowledge too, the difference between "still true" and "nobody has looked since July 11." The CLI surface was left alone; it was gardened all week.
* **Correction**: the [agent skill](capabilities/agent-skill.md) named the verbs it teaches as produce, migrate, maintain, consume, and search — five of the seven its own command table carries. `curate` (validate + lint + loose, structural upkeep that hands to `maintain` once the *content* has drifted) and `doctor` (assume nothing: install and verify the CLI, then the bundle) were missing, and the no-argument menu with them. An enumeration that stops short reads as whole — nothing inside it points at the entry that should be there and isn't, the same blind spot the §6 map covers for [index listings](capabilities/read-views.md). Caught while consuming the concept to summarize the skill: a reader's question was the check neither `validate` nor `lint` can run.
* **Creation**: [static render](capabilities/render.md) became its own capability — the seventh — extracted from the [graph server](capabilities/graph-server.md) it had lived inside as a section. The signal that it wanted its own file was that the rest of the bundle already reached for it: the [trust boundary](design/server-trust-boundary.md) linked `okf render` by name, [integration first](design/integration-first.md) told its `render -o` exit-code story — and a heading others cite on its own is a concept wearing a section's clothes. It answers a question the live server does not: not "can I explore it" but "can I ship it where nothing runs," the same page with `EMBED` swapping live endpoints for an inlined payload, one template and no second renderer to keep in sync. The section that held it is now a pointer, so the shared page-and-template story stays in one place while render owns the export-specific half — the weight it trades for needing no server, and the flags baked in because a static file cannot be told them later. The [overview](overview.md), both indexes, and the [CLI](cli.md)'s verb table read seven now. The lesson is the atomic-concept one from the other side: a capability documented only as a subsection of its sibling is reachable by whoever already knows to look inside the sibling, and by no one else.
* **Sync**: the user-facing name for one registered bundle became a single token, `@slug`, and the bundle followed the README and [skill](capabilities/agent-skill.md) in adopting it. Every command banner and the `okf help` map now read `<dir|@slug>` in one spelling, with a note under the map defining the token, where the grammar used to set `slug` beside `@ref` and explain the pair once — in prose at the foot of `okf help`, past where a reader who already knows the verb ever looks; [cli.md](cli.md), the [registry](registry.md), and [search](capabilities/search.md) drop `@ref` for the single-bundle form to match. What stays is the tell: "ref" survives only where flattening it to `@slug` would be false — `@all` is still *a ref, not a flag*, and the one `resolve_ref` seam resolves slug, bare `@`, and `@all` alike. Retiring a piece of jargon is not erasing the mechanism it overnamed: the umbrella was real, and only its use as the everyday word for one bundle was the confusion.
* **Sync**: [`--help`](cli.md) stopped being the one command surface the injected streams could not reach. It had been OptionParser's officious handler, which prints to the process's own stdout and ends in `exit` — so the first test to ask any command for help took the whole runner down with it, mid-run and green, which is why in this suite no test ever had. Each parser now writes its banner to the injected `out:` and throws `:help` back to `run`, which returns the caught status like every other path, and the [integration base](design/integration-first.md) flunks with the offending argv if any path calls `exit` instead. The [CLI](cli.md) concept already claimed the whole surface was driven in tests; `--help` was the clause that made it not quite true, and closing it is the difference between a property asserted and one that merely holds until someone tests the exception.
* **Correction**: the [registry](registry.md) normalized a slug on the two paths that write one and not on the third that reads one, and that single asymmetry paid out three ways. A hand-typed `"slug": "My Docs"` listed while `@my-docs`, `rename`, and `default` all missed it — the verbs that could repair the entry were the ones that could not see it, the same dead end the reserved `all` row had, one step wider. It was also the [graph server](capabilities/graph-server.md)'s XSS trigger: slugs reach the bundle switcher's HTML, its JS escape covered `& < >` but not quotes, and an un-normalized read was the only way a quote could ever reach a slug. And `registry del ./notes` fell through the same normalization to delete an entry pointing somewhere else entirely, reporting success. One rule missing from one path, three unrelated-looking bugs — worth remembering when the next one looks local. (The escape was hardened anyway: a page whose safety rests on a guarantee three layers away is not one you can reason about where you read it.)
* **Correction**: two verbs counted the same concepts into inventories that would not reconcile. `Graph.default` was widened so a whitespace-only `type` buckets as `Untyped` — §9.2 makes it as non-conformant as a missing one — but [lint](capabilities/linter.md) kept its own `type || "Untyped"`, which only catches nil, so `okf lint` reported a `"  "` bucket that `okf types` had never heard of. The rule was spelled twice and only one copy was widened. A shared rule with two spellings is a rule with a half-life.
* **Correction**: `search --fields slug` on a path-named bundle passed the typo guard and answered `matches:[{},{},{}]` under `count: 3`, exit 0. The match shape had been declared as the *union* of both modes so `--fields slug` would never read as a typo — but only registry mode labels its rows, so the guard accepted a name the projection could not fill. `ROW_FIELDS` exists to keep the guard off the *data* (an empty result still knows its field names), not to merge two views under one name: the modes emit different rows, so they declare different shapes, and a path-named search now names the fields it actually has. A refusal that lists the alternatives beats an answer shaped like an answer.
* **Correction**: the reserved-slug fix recorded below overcorrected within a day. Refusing a registry file whose row claimed `all` treated an unusable *name* as a malformed *file* — so one legacy row took every healthy entry down with it, and `registry del`/`rename`, the two verbs that could fix it, died on the very read they needed to survive. Hand-editing JSON was the only way out of a state the gem itself could produce: every release before the reservation slugged a directory named `all/` exactly that. The [registry](registry.md) now mints around it on read, as it already does when registering `all/` — the entry answers to `all-2`. Two lessons, and the second is the one worth keeping. A guard is only as good as its failure mode: this one made the disease (one unnameable entry) better and the cure (an unreadable registry) catastrophic. And a reservation is a *migration*, not just a rule — the moment a name becomes illegal, some file already on disk is holding it, and the rule has to say what happens to that file. This one said "reject", which is the one answer that cannot be applied to a file you have already shipped.
* **Correction**: §9's best-effort read had a hole where the errno gets in. `bundle.unparseable` tolerates a file whose *frontmatter* will not parse, but a file that will not **open** threw `Errno::EACCES` straight out of `Bundle::Reader` — and the read is the one path every verb shares, so one locked file broke `lint`, `validate`, `catalog`, `server`, and `registry set` alike, as a backtrace under exit 1 (which the [CLI](cli.md)'s contract spends for "non-conformant bundle", a claim nothing had established). "One bad file never breaks the rest" was a promise the [model](model/bundle.md) made and one layer did not keep. It joins the same bucket now, reported under §9.1 with the file and the errno. The shape is worth naming: the tolerance was written against the failure that was *interesting* (malformed authoring) and not the one that was *boring* (a file mode), and boring failures are exactly what a shared read path meets in the wild. Found while chasing something else — the [hub](capabilities/graph-server.md) dropped a bundle the listing starred, and the reason the hub dropped it was this.
* **Sync**: [integration first](design/integration-first.md) gained the rule that orders the work — a change earns a *red* integration test before it earns a patch, and the failure has to be read rather than merely seen, since one that fails on a missing fixture proves nothing about the bug. The two corrections below were fixed that way and the concept cites the first: the red run printed both halves of the disagreement at once, `/` redirecting to one bundle while the listing starred another. Written afterwards a test can only certify the code it was read off; written alongside, a bug and its test come to agree with each other — the same "green suite certifies a bug" the concept already warned about, reached from the other side. Recorded in AGENTS.md too, which is what `.claude/CLAUDE.md` loads.
* **Correction**: making the default a *position* left two derivations of it, and they disagreed. [`registry list`](cli.md) computed the star from raw order while the [hub](capabilities/graph-server.md) computed it from the bundles it could actually load — so a registry whose first entry had vanished starred `gone (missing)` while `/` redirected to the next bundle. Both readings were defensible and one had to be wrong: the star means "the bundle a bare `okf server` opens", so it must skip exactly what the hub skips, and the [registry](registry.md)'s default is now the first entry *still on disk*. Its mirror fell out of the same rule — `registry default <slug>` must refuse a vanished directory, or the move would answer with a slug the user never typed. The mechanism is worth more than the bug: the [old design stored the default](registry.md), so both readers read one field and could not drift; deriving it made the field free and the *agreement* the thing to maintain. A derived value with two derivations is a foreign key wearing a disguise.
* **Correction**: `all` was reserved on the two paths that *mint* a slug and not on the third that admits one — reading the file. A hand-typed `"slug": "all"` therefore listed and mounted perfectly well while no `@ref` could name it, since `@all` means every registered bundle: present but unreachable, which is precisely the shape the read-time shape checks exist to keep out. The reservation also leaked the other way, out of the registry and into `Registry.dedupe`, which the *ephemeral* hub mints through too — so `okf server ./all` invented a `/b/all-2/` whose `/b/all/` did not exist, dodging a collision with nothing. Reserving is the registry's business, because the registry is the only world with a grammar that spells `all`. One rule landing in the wrong layer under- and over-reached at once.
* **Sync**: three simplifications landed before the registry ever shipped, and the bundle records the design rather than the removals. `$OKF_HOME` is the [CLI](cli.md)'s single lever on which registry a verb reads — the `--home` flag it replaces had to be remembered on the three verbs that offered it and forgotten on the eleven that did not, to name a location the env var already named. The [registry](registry.md)'s default became a **position**: the first entry is the default and `registry default <slug>` moves it there, because a stored slug is a foreign key into the same list it lives in, and every operation owed it referential integrity — carry it through a rename, re-point it after `add --as`, clear it on a remove, fall back when it dangled anyway. Position owes nothing, and a dangling default is now unrepresentable rather than handled. And "every registered bundle" became the ref `@all` instead of a `--all` flag: the flag *reinterpreted the positionals* (`search .okf home` read `.okf` as the bundle, `search --all .okf` as a term), so [search](capabilities/search.md)'s diagnostics existed only to explain the flip. As a ref there is one grammar — slot 1 is always a bundle identity — and both diagnostics are gone. `all` is reserved as a slug, which is the registry's own "may invent a name, never substitute one you chose" rule reaching one name further.
* **Correction**: [search](capabilities/search.md) claimed `--all` took no directory — "one passed anyway is a usage error, because demoting it to a search term would answer a confident 'no matches' for a bundle nobody searched" — and the code did the opposite: it noted the demotion on stderr and searched, deliberately, so the command's fate would not depend on the cwd it ran in. The prose described a design that was considered and rejected; the CHANGELOG's unreleased notes carried the same false claim. Neither `validate` nor `lint` can catch a sentence that is merely untrue, which is what this log is for. Moot now — `@all` cannot take a directory to refuse — but recorded, because the *mechanism* is not: a rejected design's prose outlived the rejection in two places at once.
* **Correction**: [search](capabilities/search.md)'s retrieval-eval citation pointed at `test/integration/cli/cli_search_test.rb`, a file the same branch deleted when the suite regrouped into [by_dir / by_registry / across_bundles](design/integration-first.md) — the concept cited its own evidence at an address that no longer resolves. Repointed at `by_dir/cli_search_test.rb`, where the eval lives. Citations are the one enumeration nothing checks: they are URLs, so neither `validate` (§9 tolerates broken links) nor `lint` follows them into the tree, and a move that renames a test file leaves the prose reading true while its proof goes missing.
* **Sync**: the gem's testing rule became a design constraint, so the bundle records it — a new [integration first](design/integration-first.md) concept: the CLI is the product, so the suite that drives it end to end outranks the unit tests; the folders under `test/integration/cli/` are the three ways a user names a bundle (by path, by ref, several at once) with one file per command *and* subcommand; `rake test:integration` measures the layer alone because the full suite's number flatters (unit tests reach code no user can), which turns coverage into a map — a hole in `cli.rb` is a hole, a gap in `bundle/writer.rb` is the [library API](capabilities/library-api.md)'s to prove; and fixtures follow common closure, one group's living under that group. It carries its own argument: `rooted` and `mentions` exist because a branch no fixture can reach is a branch nobody has ever proven.
* **Sync**: [`graph`](capabilities/read-views.md) was the last view that named no bundle — a bare pair of counts over a bare `nodes`/`edges` payload, by path or by ref alike. It carries the same identity head as every other view now, so the [read views](capabilities/read-views.md) concept can state the rule without an exception hiding under it.
* **Sync**: the [CLI](cli.md)'s exit-code table gains the subtle member — a *second* bundle is a usage error, because only `search` merges and only `server` mounts several; reading the first and dropping the rest answered confidently about a bundle nobody asked about. A bad `-o` path joins it: exit 2, not a backtrace.
* **Correction**: the [graph](model/graph.md) concept's `type_index` said nothing about blank types, and the code sorted `nil`, `""`, and `"  "` into three buckets — one of them a row labelled with spaces — while §9.2 and the [validator](capabilities/validator.md) reject all three identically via `OKF.blank?`. Folded to one `Untyped`, and the concept now says which spellings land there.
* **Sync**: every bundle-scoped output now names its bundle in the identity the caller used — the [CLI](cli.md) records the two-keys-one-meaning rule (`bundle` is always a directory, `slug` always a registry slug), the `@handbook (/path)` human header, and why a path-named bundle carries no slug (inventing one implies a registration that does not exist; looking one up would cost a registry read on every plain-dir run). [Cross-bundle search](capabilities/search.md)'s head became `bundles: [{ slug, dir }]` so a row resolves to `<dir>/<id>.md` without a second lookup, and its rows carry `slug` — the key that used to be `bundle`, which meant a *directory* in single-bundle mode and a *slug* here. One key, two meanings, chosen by invocation form: the shape most likely to make an agent confabulate the bundle a concept came from.
* **Correction**: an xhigh multi-agent review caught what four reviewers missed, and the [CLI](cli.md) and [registry](registry.md) concepts now record the rules the fixes established. A registered slug reserves its mount before any plain dir's basename is deduped (`server ./two @two` was handing `/b/two/` to the *unregistered* directory). Lookup normalization no longer inherits the mint-a-name placeholder, so `@***` is a bad ref instead of whatever bundle is slugged `bundle` — the deeper cut of the registry's own "may invent a name, never substitute one you chose" rule. The registry checks its file's *shape*, not just its JSON syntax, and the CLI loads it through a guard, so a hand-edited file reaches the user as a usage error rather than a backtrace from a verb that never rescued one. A `registry` subcommand hiding behind a flag is now a usage error rather than a silent no-op at exit 0.
* **Sync**: `--home` grew a coherent rule — it steers @refs wherever a verb offers it (`registry`, `server`, and now `search`), and `$OKF_HOME` backs every verb that does not — replacing the earlier "--home never steers a ref". [`search`](capabilities/search.md) also records that `--all` takes no directory: one passed anyway would demote to a search term and answer a confident "no matches" for a bundle nobody searched.

## 2026-07-16
* **Correction**: the [graph server](capabilities/graph-server.md)'s responsive section claimed a `≤1024px` breakpoint and justified it as a statement about touch input — "tablets included… the tablet line rather than the phone one". The code's breakpoint is `≤768px` (phones and portrait tablets), so the rationale was not merely off by a number but backwards: a landscape tablet crosses `769px` and gets the *desktop* layout. The number came from a superseded commit message instead of the template — the exact drift this bundle exists to prevent. Rewritten against the CSS: the breakpoint tracks the width available to the chrome, not a device class, which is why rotation re-evaluates it.
* **Sync**: `okf registry list --json` now answers in the object envelope every other `--json` view uses — `{ registry, count, bundles }` — naming the registry file it read, so a `$OKF_HOME` mismatch is visible in the payload; the skill reference records the shape.
* **Correction**: a four-perspective review (skeptical, end-user, skill-writer, retrieval-agent) of the @refs work landed fixes on both sides. Code: `search @ @one` no longer searches one bundle twice (dedupe by resolved path), a reused `OKF::CLI` instance no longer leaks ref slugs between runs, `@One` now resolves like registration slugified it, the not-registered error names the registry file consulted, the gone-directory error names the next move, and the @-grammar traps announce themselves on stderr. Docs: the [CLI](cli.md) names the real resolution seam (`resolve_ref`, not `positional_dir`), scopes `--home` out of @refs on every surface, and corrects "the one verb that takes several refs" to "the one verb that *merges*" (the server takes several too); [search](capabilities/search.md) documents the JSON envelope switch, the literal `--fields` projection, and the literal-@-term escape; the skill's search playbook finally teaches the spanning it executes.
* **Curation**: added the `registry` tag connecting the [bundle registry](registry.md), the [CLI](cli.md), and [search](capabilities/search.md) — the retrieval review showed the feature's concepts were findable by body text but invisible to the tag vocabulary.
* **Sync**: caught the bundle up with @refs and cross-bundle search — the [CLI](cli.md) records that every `<bundle-dir>` now also takes `@slug` (a registered bundle) or bare `@` (the registry default), resolved in one seam and failing hard on an explicit ask; the [bundle registry](registry.md) gains its grown role as the CLI's name-resolution layer, not just the server's boot list; and [ranked search](capabilities/search.md) documents the one cross-bundle verb — several leading @refs or `--all`, merged rankings labeled per bundle, `--all` forgiving a vanished directory while explicit refs are strict — plus why the graph deliberately stays per-bundle.
* **Sync**: caught the bundle up with the unreleased bundle registry and multi-bundle hub — a new [bundle registry](registry.md) concept (the per-user JSON list under `$OKF_HOME`, the forgiving-implicit/strict-explicit slug rule, the chosen default and its first-entry fallback, path-as-identity, the `missing` marker over silent pruning, and the atomic write) enumerated in the root index, the [overview](overview.md), the [CLI](cli.md)'s Act group, and the [core/shell split](design/core-shell-split.md)'s shell list and diagram. The [graph server](capabilities/graph-server.md) records the hub (`/b/<slug>/` mounts paid for by the page's already mount-relative endpoints, the default redirect, the browsable `/b/` index, the boot-time read that makes a change need a restart), the server-only bundle switcher, and the ≤768px responsive chrome; the [library API](capabilities/library-api.md) notes that the registry and hub load on demand, so the embedding surface stays fixed.
* **Correction**: the [graph server](capabilities/graph-server.md)'s gzip section named `run_server` as the boot seam that wraps `Rack::Deflater`; the seam is now `serve`, the one path both a single bundle and a hub pass through — which is what makes the wrap total rather than per-mode.
* **Sync**: the plugin's `/okf:gem` command became a pass-through shim — the [agent skill](capabilities/agent-skill.md) now records that all routing (Commands table, intent inference, the not-a-bundle `migrate` suggestion) lives only in `SKILL.md`, where the drift test guards it, and the command just hands its arguments to the skill unchanged.
* **Sync**: caught the bundle up with the skill's new `migrate` verb — the [agent skill](capabilities/agent-skill.md) now records the second authoring on-ramp (adopt existing documentation in place: frontmatter and reserved files added, bodies kept verbatim, `okf validate --json` as the worklist) alongside `produce`'s distillation, and its plugin-channel section notes that `/okf:gem` suggests `migrate` when its target directory turns out not to be a bundle.

## 2026-07-15
* **Sync**: caught the bundle up with the unreleased gzip transport — the [graph server](capabilities/graph-server.md) now records that `okf server` gzips every response a client accepts (`Rack::Deflater` wrapped at the `run_server` boot seam), transparent to the browser and at [no new dependency](design/runtime-dependencies.md) since Deflater ships inside the `rack` already required; the note draws the boundary that the wrap is boot policy, not the app — a host mounting `OKF::Server::App` and the static `okf render` file each carry their own compression — and adds the reciprocal edge into the runtime-dependencies constraint.
* **Sync**: caught the bundle up with the unreleased `okf render` verb — the [graph server](capabilities/graph-server.md) now documents its static twin (one command writes the whole page as a single self-contained file, the bundle baked in, to host where there is no server) and the data-access design that makes one template serve both modes: the browser's reads flow through getter functions whose source an injected `EMBED` switch selects — live `fetch()` under `okf server`, the embedded payload under `okf render`. The [server trust boundary](design/server-trust-boundary.md) records that render inlines each body through `json_for_script` and still sanitizes it with DOMPurify, so the embedded path carries both defenses; the [CLI](cli.md) verb table gains `render` (Act, best-effort), and the [overview](overview.md) and [capabilities](capabilities/) index listing note the static export.

## 2026-07-13
* **Sync**: the [graph server](capabilities/graph-server.md) gains a fullscreen diagram viewer — a rendered Mermaid block is now click-to-inspect (re-rendered from source into a pan-and-zoom overlay, Panzoom lazy-loaded beside Mermaid), and the concept's self-contained-page section records the two lazy CDN assets.
* **Sync**: caught the bundle up with the server's authored-layer round — the [graph server](capabilities/graph-server.md) now renders the §6 index map and §7 log in the browser (the Files | Indexes tree tabs), resolves in-app links to reserved files and bare directories, and lets folder/area nodes open their directory map, all backed by new `/index` and `/log` endpoints; this closes the parity gap from the other side of search — the CLI had the map, now the browser does too.
* **Sync**: caught the bundle up with the unreleased `search` verb — a new [ranked text search](capabilities/search.md) concept (the pure `OKF::Bundle::Search`, its weights, snippets, and the retrieval eval), the capability now enumerated in the [overview](overview.md) table and diagram, the [CLI](cli.md) verb table, the [read views](capabilities/read-views.md), the [library API](capabilities/library-api.md) standalone pieces, the [core/shell split](design/core-shell-split.md) core list, and the root and [capabilities](capabilities/) index listings; the [agent skill](capabilities/agent-skill.md) now records its search playbook and search-first routing.
* **Sync**: caught the bundle up with 1.2.0–1.4.0 — the [agent skill](capabilities/agent-skill.md) gains the Claude Code plugin channel (generated copy, `rake plugin:sync`, drift test, `/okf:gem`, curation hook), and the [graph server](capabilities/graph-server.md) gains link-preview metadata plus the UX round: in-app relative-link navigation, file-tree mode, resizable persisted panes.
* **Curation**: pruned the tag vocabulary from 39 to 23 — dropped the group-name echoes (`format` inside `format/`, `model` inside `model/`, `overview` on the Overview) and the singleton title echoes (`bundle`, `concept`, `validation`, `linting`, `library`, `api`, `skill`, `links`, `citations`, `frontmatter`, `dependencies`, `compatibility`), and merged `purity` into `pure`, which now connects the [core/shell split](design/core-shell-split.md) to the three pure model components.

## 2026-07-12
* **Sync**: caught the bundle up with the gem at 1.1.0 — the [graph server](capabilities/graph-server.md) now sanitizes each fetched body with DOMPurify before rendering, so the [server trust boundary](design/server-trust-boundary.md) closes the on-demand render path (its [design listing](design/) reworded to match), and the [library API](capabilities/library-api.md) notes that `require "okf"` loads the library alone now that the CLI and skill load on demand.
* **Sync**: caught the bundle up with the CLI at 1.0.0 — documented the new `index` command (the §6 progressive-disclosure map, the read view that sees the reserved `index.md` layer), compact-by-default JSON with `--pretty`, and `--fields`/`--except` projection on the list views, in [read views](capabilities/read-views.md) plus the `index`-verb enumerations in the [CLI](cli.md), the [overview](overview.md), and the [capabilities](capabilities/) index listing.

## 2026-07-11
* **Creation**: seeded the bundle documenting okf-gem's capabilities at version 0.1.0 — the [overview](overview.md), the [CLI](cli.md), and the [format](format/), [model](model/), [capabilities](capabilities/), and [design](design/) areas.
* **Update**: added Mermaid diagrams (tagged `diagram`) to five concepts — [overview](overview.md), the [core/shell split](design/core-shell-split.md), the [graph server](capabilities/graph-server.md), the [library API](capabilities/library-api.md), and [cross-links](format/cross-links.md).
* **Sync**: caught the bundle up with the CLI — documented the new `types` command, the cross-view `--type`/`--area`/`--tag` filters, and `tags --by type|area` in [read views](capabilities/read-views.md), the [CLI](cli.md) front end, the [graph](model/graph.md) indexes, and the [capabilities](capabilities/) index listing.
