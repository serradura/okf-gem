# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`okf dirs <dir|@slug> [--json]`** — the bundle's directories (its clusters)
  with the number of concepts living **directly** in each, root first and the
  total last. Every dir the tree has, including the empty intermediates that
  exist only to connect it — a dir holding nothing but sub-directories reads
  `0`, not a hidden rollup, so the column sums to the bundle's concept count.
  JSON: `{ bundle, total, count, dirs: [{ dir, count, subdirs }] }`.
- **`--depth N` on `index` and `dirs`** — how many directory levels below the
  starting point to keep, where the starting point is the `--dir` when one is
  given and the bundle root otherwise. Relative rather than absolute, so
  `--dir a/b --depth 1` reads "a/b and one level under it" without first working
  out how deep `a/b` is, and the two flags walk a tree a level at a time.
  `--depth 0` is the starting point alone; anything but a whole number is a
  usage error (exit 2). This is what makes `index` usable at scale — every
  directory in it is a section, so a few hundred concepts is a map nobody reads
  whole. On one such bundle `index --no-body` went 12.5 KB → 1.3 KB at
  `--depth 1`, and `index --json` 311 KB → 2.6 KB with `--depth 1 --except
  body,listing`.
- **`--dir` on `index` and `dirs` brings the chain up to the root with it**, so a
  branch is never shown adrift of the authored context that says what it is —
  the root `index.md`'s prose first among it. Those rows print with a leading
  `↑`, carry `ancestor: true`, and stay out of `total`; `--no-ancestors` drops
  them. Ascent and descent are separate axes, so `--depth` never bounds the
  chain: `--dir X --depth 0` is X alone, plus how you get to X. A `--dir` that
  names nothing gains no chain, since a lone root row would read as a partial
  answer to a query that in fact matched nothing.
- **`dirs` gains `--dir` (repeatable) and a `subtree` count** per row: the
  concepts at or below that directory, defined as exactly what `--dir` on the
  row returns, so the number and the flag can never disagree. Without it a
  truncated listing is all zeroes at the top of a deep tree — which is where
  "where is the mass?" is actually asked. The human table shows the column only
  where some directory nests; `--json` always carries it.
- **`--dir PATH`** joins the shared filter set on `search`, `catalog`, `files`,
  `types` and `tags`, and `index` gains it as a repeatable selector. One rule:
  a concept matches when its dir *is* the path or sits below it — so `--dir
  platform` reaches `platform/services/api`, `--dir platform/services` narrows,
  and `--dir .` means the root alone with no special case. `root` is the
  unquoted spelling of `.`; matching folds case.
- **`tags --by dir`** cuts the tag index by the whole directory path, where
  `--by area` only ever saw the first segment.
- **`stats` gains `dirs` and `by_dir`** (the full-path cut, direct counts), and
  its human breakdown now reads **By dir**. Both are read off the same map `okf
  dirs` lists and `--dir` is answered against, so the two verbs cannot report a
  different number of directories — a directory holding nothing directly appears
  at `0` rather than being dropped, since it is still one `--dir` addresses.
- **Search rows carry `dir`** — the full path, `.` at the root — beside the
  first-segment `area` they already had.
- **`dirs` takes `--fields`/`--except`** like the other list views, over the row
  shape it already declared.
- **A single-bundle `okf server` answers `GET /search?q=`.** The route was the
  hub's alone — conceived as the *cross-bundle* one — which left `okf server
  ./docs` with a ⌘K palette that could find nothing, though one bundle is a legal
  one-element set. `App` owns the payload and the hub calls it, so the shape is
  defined once; a row from a single-bundle server carries no `slug`, which is how
  it avoids answering as if it were a set. A static `okf render` still advertises
  no endpoint: there is no server behind it to ask.
  - **The route always answers; advertising it is the caller's call.** The page
    resolves the endpoint *relative to the URL the reader is on*, so only whoever
    mounted the app knows what to call it: `okf server` mounts at the root and
    passes `search`, while `App.new(folder)` on its own advertises nothing, since
    a default would point an app mounted at `/knowledge` back at its host's root.
- **The search index is built once and held.** Every request used to rebuild the
  whole corpus — measured 1.45 s per search on a 414-concept bundle, flat across
  repeats, with the build ~95% of it. `Search.prepare` holds a corpus (documents,
  the key→concept map, the built index) and `Search.with` queries it: **0.016 –
  0.052 s** per search, with the 1.39 s build moved into boot, where `okf server`
  warms it deliberately. An engine opts in by exposing `prepare`; the scan
  declares none and is handed none, so no engine or addon had to change. The
  trade is staleness — a corpus is a snapshot, like the graph — and the hub drops
  its corpus on any registry write, since a held index outliving the set it was
  built from is a wrong answer rather than a slow one.
- **`⌥ drag` moves a cluster box**, and is listed in the `?` sheet.

### Changed

- **A bundle is named by its slug, everywhere it is chosen.** The ⌘K switcher,
  the Bundles panel and the hub's `/b/` page all led with the derived
  `parent/dir` label and left the slug in muted grey beside it — the address in
  the name's place, when a bundle is addressed by `@okf-gem` and `/b/okf-gem/`.
  Rows now carry `@slug` as the name and the folder as the fact under it, shown
  only where it is not the name repeated. `/b/` drops the short label outright:
  it only ever stood in for the full path, which is on the row already.
- **A `.okf` directory is labelled by the project that holds it.**
  `Bundle::Folder.label` reads `repo/.okf` as `repo`. The `parent/dir` pair
  exists because a bundle directory's own name is rarely unique — except when it
  is `.okf`, the conventional container, and then a registry of eight projects
  was eight rows all saying `.okf`. This also reaches `okf registry list` and the
  default `okf server` title. (A `.okf` with no parent to borrow keeps its own
  name; that case used to compose into `//.okf`.)
- **A force layout settles, then moves once.** `animate:true` reads to these
  engines as "render every tick of the simulation" — the visible bounce, and
  hundreds of full re-renders for one settle. It is `'end'` now: the same
  simulation run headless, the nodes moved once into the same final positions.
  Past 250 nodes even that transition is dropped, because at that size the move
  itself is the jank.
- **A cluster box is scenery, not a handle.** Its empty interior is the largest
  drag target on the canvas, so dragging to look around dragged the *directory*
  instead of the view — worse the bigger the cluster. It takes `grabbable:false`
  **and** `pannable:true`: ungrabbable alone stops the box moving, but the node
  still swallows the drag, and it is `pannable` that hands the gesture to the
  canvas the way empty background does. `Alt`+drag gives the handle back, since
  moving a box is a real gesture, just not the constant one — `Alt` rather than
  `Ctrl`, which on macOS is the system secondary click. A tap still opens the
  directory's map.
- **`f` is no longer a shortcut.** A bare letter bound globally fires on every
  keystroke the page did not route into an input, and fullscreen is not a mode to
  enter by accident. The button stays and is now the only way in; the shortcut
  sheet no longer advertises a key nothing is bound to.
- **The skill names one first move.** It had prescribed three different ones
  across seven places — SKILL.md, four playbooks and the CLI reference — and that
  disagreement is the deliberation an agent pays for on every retrieval. Every
  site now says `okf dirs` first, then `okf index --dir <branch>` to descend,
  chosen structurally: `dirs` emits one row per *directory* where `index` emits
  one listing row per *concept* even under `--no-body`, so the two scale with
  different things.

- **Cluster mode nests.** The graph page grouped concepts into one flat row of
  boxes, one per *first path segment* — the same lossy projection `--area` was.
  A cluster is a directory now, and the boxes nest as the directories do, to a
  depth picked from a select beside the layout one. Depth **1** is the default
  and draws exactly the old view; a flat bundle is offered no control at all.
  At depth N every directory of depth ≤ N gets a box (intermediates that hold no
  concepts of their own included, since they hold sub-boxes), and a concept
  attaches to its own directory's box truncated to N. The root box still holds
  direct-root concepts and never nests another. Box ids carry the directory
  verbatim (`box::platform/services`, `box::.`), so a tap opens that directory's
  map with no label to unmangle.
- **The page speaks `dir` too**: the filter group is **Dirs**, listing every
  directory (not just first segments) and filtering by the same
  directory-and-below rule `--dir` uses — in the graph, catalog and tags views —
  and the Stats panel's breakdown is **By dir**, keyed by the whole path.

### Fixed

- **The rail marks Index while the root map is open.** Index is a shortcut into
  Files, so the two share one `data-view` — and the rail read only that, lighting
  **Files** on the one screen a reader reached by clicking **Index**. The open
  file is what distinguishes them, so it is what the rail reads; a *nested*
  `index.md` is still Files.
- **`--dir` accepts the label the views print.** `fold_dir` never stripped a
  trailing slash, while `okf index` labels a row `tables/` — so pasting a printed
  row back into the flag matched nothing and exited 0, an empty result under a
  count that agreed with it.
- **The `--dir` chain keeps its case.** It was walked over case-folded paths and
  then matched against the map with `include?`, which does not fold, so every
  ancestor of a directory spelled with a capital vanished from the chain that
  exists to place the branch.
- **`--area` with `--depth` or `--dir` is refused (exit 2)** instead of unioning
  the area with what the other flag selects. The deprecated flag is exact: with
  `--depth` it names no starting point to be relative to, and with `--dir` one
  side is exact where the other is a prefix, so the map came back with the area
  *and* the subtree — an answer to neither question. A deprecated flag that
  quietly widens is worse than one that is merely old.
- **A cleared filter no longer leaves a cluster unlaid.** The tiling runs over
  the visible elements only (fcose throws on a node whose label went
  `display:none` mid-run), but nothing re-tiled when a filter was later loosened —
  so concepts hidden when clustering began came back at their pre-cluster
  coordinates and stretched their box across the canvas. Worst case the filter
  matched nothing, the layout returned early, and clearing it showed a view
  nothing had laid out at all.
- **A palette hit in a single-bundle server no longer 404s or reloads the page.**
  A row with no `slug` was read as naming a *foreign* bundle, so the href became
  `../undefined/`, the row rendered an "undefined" chip, and the click took the
  page-load branch — reloading the whole index to reach a node already on screen.
  Three sites, one absent field.
- **A focused form field no longer zooms the page on iOS.** Safari zooms whenever
  a focused control is under 16px and never zooms back out, so on a phone every
  `/` left the reader pinching to recover. Keyed on `(max-width:768px)` *or*
  `(pointer:coarse)`, because neither covers the other — a phone is narrow, a
  tablet in landscape is not and zooms just the same.
- **A nested cluster no longer throws when a filter empties it mid-layout.**
  fcose measures every node it is handed, so hiding nodes while its tiling
  animation ran threw on a label it could no longer measure. The layout is
  handed the visible elements only — which is also the right answer, since a
  hidden concept has no business influencing where the visible ones land.
- **An intermediate directory box no longer takes its branch off the canvas.**
  The empty-box rule read a compound's direct children, and a box holding only
  sub-boxes has none, so it always counted as empty. It reads leaf descendants
  now.

### Deprecated

- **`--area`, and `tags --by area`.** OKF's own vocabulary for grouping is
  *directories* (`grep -ci area SPEC.md` → 0); "area" was this gem's invention,
  and defining it as a concept id's first path segment threw away every level
  below it. `dir` is now the only machine word — full path, `.` at the root,
  rendered `(root)` for humans — and "cluster" stays prose for what a dir
  groups. Both deprecated spellings keep their **old behavior exactly** and warn
  once per run on stderr (`--json` on stdout is unaffected); they go in a later
  release, along with `by_area` and the `area` row field.

## [1.10.0] - 2026-07-21

### Added

- **The skill gains a `refine` verb** (`playbooks/refine.md`): restructure a
  bundle to get the most from OKF's capabilities — progressive disclosure, the
  emergent graph, cross-cutting tags, capture-once-link-many. It is the third
  authoring boundary: `curate` keeps the structure sound as it stands,
  `maintain` keeps the content true, `refine` changes where knowledge lives —
  evidence-first (tag locality, the hub origin test, a fatness alarm),
  cohesion-over-balance, free levers before file moves, and it *proposes* (a
  report plus a frozen execution prompt), never auto-applies.
- **`okf graph --hubs`** — the inbound ranking: every concept with at least one
  inbound link, ranked by inbound degree, each with its links grouped by
  *source area* (`core/status  ×3   flows 2, billing 1`). This is the refine
  playbook's hub origin test made mechanical: a hub whose inbound majority is
  foreign to its own area is a move candidate. JSON: `{ bundle, count, hubs:
  [{ id, area, inbound, by_area }] }`.
- **The registry has a browser surface.** A meeting with non-technical readers
  settled what the TUI could not: `okf registry set/del/default/rename` is the
  right surface for the people who *write* bundles and the wrong one for the
  people who read them. The graph page's rail grows a **Bundles panel** behind
  ⚙ — every bundle the server knows about, with its title, `@slug`, folder,
  concept count and a health verdict — and four routes behind it:
  `POST /registry/{default,rename,remove,add}`, the only non-GET routes the
  server has.
  - **Management is the default, and `--read-only` declines it.** The flag names
    the restriction rather than the capability, because the audience this was
    built for should not need a command line to use the page they were pointed
    at. A loopback bind is writable without a flag; any other address is refused
    outright, with no flag that opens it — `--bind 0.0.0.0` is how a personal
    tool becomes a public one, and a write surface does not follow it there.
  - **Four gates on every write**: is this server writable at all; is there a
    registry to write to (an ephemeral `okf server ./a ./b` answers `409` rather
    than leaving the missing controls a mystery); is the verb one of the four (a
    frozen list — "call whatever method the path names" is how a router becomes
    an `eval`); and did this come from this page (same-origin *and* a per-boot
    token, since the token lives in a page another site can get a reader to
    submit, and Origin alone would trust every tab open on the host). A
    read-only server hides the controls *and* refuses the request that skipped
    them: hiding a button is a UI, refusing the request is the boundary.
  - **A write rebuilds the hub's bundles from disk** before it answers. That is
    the step easy to skip and impossible to skip safely — a write leaving the
    running server on the old set is a lie the next click believes.
  - **`/b/` stops managing and keeps the page.** Both surfaces carried the same
    four verbs for a while, and two implementations of one contract is the thing
    that drifts, so the forms came out and the routes stayed. `/b/` answers
    *which bundles are there* — and remains the empty state a hub with zero
    bundles still needs — while the panel answers *change this one* where the
    reader already is. With nothing to post it holds no token either.
  - **There is no Add on either surface.** A browser cannot hand over a
    filesystem path — the File System Access API yields an opaque handle, and is
    Chromium-only besides — so registering stays the agent's act. The route
    exists for other callers; nothing in the UI reaches it.
  - **"Workspace" is retired** from the docs and the UI. The things are Bundles
    and the thing holding them is the registry; a page saying one word while the
    CLI says another is two products wearing one name.
- **The hub searches every bundle it hosts.** `GET /search?q=` is the only route
  in the server that knows about more than one bundle: `Search.across` over one
  shared index, so BM25 weighs a term against the whole corpus instead of
  stapling per-bundle lists together. Capped at 50 with the total reported,
  because a silent cap reads as a complete answer. The engine is named `:index`
  outright rather than left to route off `fuzzy: true` — that reached the right
  engine only because nothing else declares the capability, which is correctness
  by coincidence, and an addon declaring `:fuzzy` would have taken the route
  silently. A long-lived server also amortizes an index build over every
  keystroke where a one-shot CLI cannot, and minifts is a port of the browser's
  own MiniSearch, so a palette hit and an in-page search rank alike.
  - **The palette's Concepts group comes last**, and not because it matters
    least: it is the only group that arrives asynchronously, and a group landing
    above the cursor moves the row under the reader's fingers between the
    keystroke and the Enter.
- **The topbar search box says what it filters, and where to go when it finds
  nothing.** It and ⌘K looked alike and meant different things — the box
  *filters* what is on screen, the palette *finds* across every bundle a hub
  hosts — and the box carried neither fact: it emptied the graph in silence and
  never mentioned the palette, so a reader whose word lived in another bundle
  got a blank canvas and no way out. Three additions, all inside the box: a
  **chip** naming the chord (⌘K / Ctrl-K, OS-aware) that opens the palette, a
  **live count** (`7/8`) that makes an empty result a number which reached zero
  rather than a view that went blank, and on zero a **panel** naming the bundle
  and the query — ⏎ hands it to the palette prefilled and already searching, esc
  clears.
- **`okf` is extensible.** Any gem that puts `okf/plugin.rb` on its load path can
  register a verb, and it answers to `okf` — listed in `okf help` under
  `installed extensions:`, dispatched like a built-in. There is no list of known
  addons in this gem and no configuration step for the user: installing the gem
  is the whole installation. It is the same seam `Search.register` opened for
  search engines, and the same idiom — append-only, idempotent by id, so an addon
  can never quietly displace a built-in.
  - **Discovery is lazy**, which is what makes it affordable. A built-in verb
    resolves against the registry and dispatches without scanning at all; only an
    unknown verb or `okf help` — which has to know everything by definition —
    pays the ~11ms `Gem.find_latest_files` costs on the 2.4 floor. A one-shot CLI
    that will not build a search index for a single query should not pay for
    discovery to answer a verb it shipped with.
  - **Extensions must come from gems named `okf-*`**, the convention Jekyll and
    Vagrant use for the same job: it makes what counts as an okf extension
    explicit and stops an unrelated gem claiming the `okf/plugin.rb` path by
    accident. One that is not so named is discovered, skipped, and reported on
    stderr. A path belonging to *no* gem — a checkout, `ruby -I`, a Gemfile
    `path:` — stays trusted, because someone put it there deliberately. It is a
    mild guard too — loading a plugin runs its code — but the naming convention
    is the reason, not the threat model, which is thin: under Bundler discovery
    is bundle-scoped anyway, so the Gemfile is already an allowlist.
  - **The rule holds when it cannot get an answer**, which is a separate promise
    from the rule itself. A gem name that cannot be read — one corrupt gemspec
    anywhere on the machine — is refused rather than treated as "belongs to no
    gem", and the refusal names the exception that caused it. A discovery that
    fails outright is reported too, since an empty list and no message is
    indistinguishable from a machine with nothing installed.
  - **A broken addon is skipped and reported, never fatal** — the same
    best-effort posture the reader takes with an unparseable file. The note goes
    to stderr, so a `--json` run's stdout stays a clean machine substrate.

- **The graph page is proven in a real browser.** `test/browser/` drives the
  page `okf server` and `okf render` share in Chromium, asserting DOM state and
  computed CSS at real viewport widths, and failing any test where the page
  threw. Every spec runs twice — once served, once against a `file://` static
  render — because the two modes diverge on fetched endpoints vs. a baked
  `EMBED`, and a pass in one proves nothing about the other. It is opt-in
  (`rake test:browser`, outside the default task) and non-blocking in CI, since
  the page boots against a CDN and a slow jsdelivr must not gate a merge. The
  three fixes below are what writing it turned up: shipped defects invisible to
  a string assertion over the rendered HTML, each reproduced red and pinned
  green.
  - **Coverage is mapped per-contract, not guessed.** `test/browser/COVERAGE.md`
    enumerates every behavioral contract the page introduced across its history
    and marks each covered / partial / uncovered against a named spec — **176 of
    181 net-live (97%)**. The five that remain are each a documented blocker, not
    a missing test: an absence-proof with no line to break, a node-overlap check
    no cytoscape layout makes both deterministic *and* mutation-sensitive, a
    map-visibility observable another contract already owns, a palette scroll
    whose observable is a tautology, and an unbuilt focus-trap. Reaching the
    branches the flat 8-concept fixture cannot took four further purpose-built
    bundles beside the hostile one, each served on its own port and baked to its
    own static page so the main fixture's count assertions stay put — nested
    directories, forty-five tags, a five-directory-deep reserved path, and a
    hundred-node ring that drives the graph past its own fit box. Every new spec
    is mutation-checked: break the code it covers, confirm it goes red for the
    predicted reason, restore. The map also caught one of its own stale rows — a
    note listed as an uncovered gap had in fact been deleted from the page, and is
    now marked superseded rather than owed.
  - **The page's CDN libraries are served from a local cache** — a read-through
    cache keyed on the request URL, so a warm run needs no network and a version
    bump is a miss rather than a stale hit; `OKF_NO_VENDOR_CACHE=1` bypasses it,
    which is how you check the pins still resolve. It buys robustness, not
    speed: measured at one worker, 28.7s without and 29.0s with, because the
    suite is CPU-bound and Chromium already reused those files across contexts.

### Changed

- **`okf tags --by` rows carry each tag's total.** The grouped view printed only
  within-group counts, so a tag's spread meant cross-referencing groups by
  hand; each row now shows `count/total` when they differ (`async  2/3`) and
  the plain count when the tag is wholly local — locality at a glance, the
  domain-vs-concern read. The JSON rows gain a `total` key; filters recompute
  it over the narrowed set.

- **A wrong turn at the hub lands on a directory, not an apology.** The 404 is
  rebuilt on the app shell, and it reads as what it is: the **asked path is the
  heading**, set in mono where a dropped slash is legible as a shape, with "not
  found" demoted to the eyebrow above it, since a reader arrives already knowing
  they are lost. A near-miss slug is a **row** wearing the same anatomy as the
  list under it, already marked, with ⏎ pointed at it; rows carry the folder
  that actually distinguishes `site/.okf` from `minifts/.okf`; and colour marks
  exceptions only, so a healthy row draws no verdict edge at all. Moving through
  the list is **Tab's** job — every row is an `<a href>`, and a hand-rolled ↑↓
  cursor was tried and deleted as a second focus model beside the real one. A
  query matching no bundle is offered the cross-bundle search that would match
  it, the same escalation the graph page's box makes.

- **On a touch screen a tap opens a card, not the whole viewport.** At ≤768px
  the inspector is `grid-template-columns:0 1fr`, so tapping a dot measured the
  stage at 0px wide: the graph was not covered, it was gone. Exploring on a
  phone became open → read → close → tap the next dot, and you could never see a
  concept and its neighbourhood at once, which is the one thing a graph is for.
  A preview card now rises at the bottom edge over a graph that keeps every
  pixel and stays live — drag it up for the neighbourhood and the body, tap a
  row and it swaps in place while the camera walks. Folder and index taps fill
  the card too; they used to write into an invisible panel, so tree and cluster
  modes were silently dead on touch. The branch is wider than the chrome's
  (≤768px, or ≤1024px portrait), because a portrait tablet has the same bug and
  wants the same gesture.

- **Type chips select instead of deselecting.** Three chip groups carried two
  grammars: areas and tags were additive — nothing selected means everything, a
  click narrows, a second click undoes — while types were subtractive, every
  type showing until you clicked one away. Same component, same panel, opposite
  meaning, and the catalog's and tags view's own type chips were already
  additive, so the rule a reader learned in one view was wrong in the next.
  Types now select, and two of them compound into a union the old model could
  not express at all — it could say "not the other four", never "Services and
  Charters". The change is a net deletion.

- **The CLI is one file per verb.** `lib/okf/cli.rb` was 1,794 lines and a
  15-arm `case`; it is now a registry and a dispatcher, with the verbs under
  `lib/okf/cli/` and the shared surface on a `Command` base class. Behaviour is
  unchanged — every existing test passes untouched — but `okf help` is now
  composed from what the commands say about themselves rather than from a
  heredoc that had to be remembered separately.

### Fixed

- Selecting a node in cluster mode faded the entire graph rather than
  emphasising the selection. Dimming set opacity on the unrelated elements, but
  in cluster mode those include the compound area boxes — and a parent's opacity
  cascades to the nodes inside it, so dimming the boxes faded the very leaves
  being highlighted. The highlight was real in each node's own opacity and
  invisible on screen: measured parent-inclusive, the selection sat at 0.1
  against an unrelated node's 0.01. `focusNode` now dims the leaves and edges
  and never the `:parent` boxes, which is a no-op outside cluster mode where
  there are no parents. After: selection and neighbours at 1, the rest at 0.1.

- A log's "Open in graph" button stayed visible, carrying a stale
  `onclick` from the last map or concept — the "answers about a different file"
  symptom, returning through CSS. The code hides it correctly
  (`#fp-graph.hidden = true`), but `.btn.text{display:inline-flex}` outranks
  `.btn[hidden]{display:none}` at equal specificity (0,2,0), so the later rule
  won and the button rendered 143px wide with the attribute present. A
  `.btn.text[hidden]` rule settles it, the same fix the sibling `.fp-head[hidden]`
  already carried.

- Leaving the graph for another view and returning redrew it at a
  fraction of its size, and stayed that way. The cause was misdiagnosed as a
  resize race for months; tracing `cy.animate`'s caller showed the one animation
  running was a *fit*. `fitGraph` computes zoom from the container's own width,
  and the one-shot boot fit (`setTimeout(fitGraph, 400)`) fires on whatever view
  is up by then — so leaving the graph inside that window fits a hidden 0×0
  canvas, `(w-2*pad)/bb.w` goes negative, and the zoom clamps to `minZoom`.
  `fitGraph` now returns early on a zero-size canvas and the graph keeps its last
  good zoom. The hazard was already known at the other end: the boot fit is not
  registered at all for a `?view=`/`?select=`/`#hash` deep link, whose comment
  names this same min-zoom clamp — it was the navigate-away case that went
  uncovered.

- `okf help`'s map advertised `search … [-e|--fuzzy]`, pairing a shorthand
  it never expanded with an unrelated flag, so the one hint that an engine is
  selectable read as though `-e` might *be* the engine switch. The row now says
  `[--regexp|--fuzzy]`, which is what the command's own banner says; `-e` still
  works and `search --help` still spells it out.
- **`okf skill <a> <b>` installed into `<a>` and exited 0.** It hand-rolled
  its own argument handling instead of using the shared pair every `<dir>` verb
  goes through, so a second destination was silently dropped — the user named two
  places and the tool wrote one, saying nothing. It is a usage error now (exit 2),
  refused before anything is written.

## [1.9.0] - 2026-07-19

### Added

- **`okf search` gains an opt-in full-text index engine.** `--engine index` — and
  `--fuzzy`, which implies it — routes to
  [minifts](https://github.com/serradura/minifts), the pure-Ruby port of the same
  MiniSearch build the graph page loads. It is the gem's third runtime
  dependency, admitted because it costs the footprint nothing the first two were
  chosen to protect: no native extension, no dependency tree of its own, the same
  Ruby 2.4 floor. Three things it adds, and nothing else does:
  - **BM25+ relevance ranking**, where the default scores by summed field weight;
  - **`--fuzzy`** — typo tolerance at edit distance `0.2 × term length`, the
    browser's own setting. Search stays exact unless you ask;
  - **parity with the graph page**, which runs the same MiniSearch build, so the
    two rank identically when the index is named.

- **`--engine NAME` picks the engine outright**, for the case a capability flag
  cannot express: a matching *model* requires nothing, so no flag selects one.
  Naming an engine that cannot do what was also asked is a usage error naming one
  that can (`--engine index -e` → *try --engine scan*), and an unknown name lists
  what is available. `--help` reads the registry, so an addon's engine appears
  without the CLI knowing it exists.

- **The graph can draw the index layer, under any layout.** The §6 map was
  visible only inside file-tree mode, where a folder node stood in for a
  directory's `index.md`. **Show indexes** makes it a layer: each map is a tile
  edged to the concepts it lists and the maps below it, dressed by the same
  selector as file-tree mode's folder node, because the two are the same thing
  twice over — clicking either opens that directory's `index.md`. Both are accent
  squares with dashed edges into them, so colour separates *kinds* rather than
  modes: a directory is not a concept and no longer reads as one. Authorship shows
  as form — solid where an author wrote a map, hollow and dashed where the bundle
  only implies one — so the toggle reads as curation as much as navigation.
  - **Moving between the modes lands in one click.** Tearing the layer down ran
    its own layout while file-tree mode ran `breadthfirst` a beat later, two
    layouts racing the same canvas; and because the layer is fetched, a promise
    resolving after a mode change could land inside file-tree mode. A `relayout`
    flag settles the first, a per-toggle ticket the second.
  - **File-tree mode disables the toggle** rather than doubling the folders it
    already draws.
  - **One label on every file's graph button.** It read "Explore the knowledge
    graph" on the root index and "Open core/ in graph" on a nested one, which made
    a single action look like three. The question is the same whatever is open, so
    the label is too — and it lives in the markup, where it cannot go stale.
  - **Opening a map from the reader keeps the reader's graph.** It forced
    file-tree mode, discarding whatever layout was running, and dimmed the canvas
    to the map's immediate neighbours. It now switches the *layer* on rather than
    the *mode* and leaves the layout alone. A reader already in file-tree mode
    stays there.
  - **Selecting anything emphasises it the same way.** A concept dimmed the graph
    to its neighbourhood, a map did nothing at all, and a folder node did nothing
    either — three meanings for one gesture. One `focusNode` now serves all three.
  - **Drawn, never modelled.** `index.md` is reserved, so these nodes are built
    from `/index` straight onto the canvas; `NODES`, `/catalog` and the type and
    tag indexes never learn they exist. Filters pass them over — a map has no type
    or tags — but a map whose concepts are all filtered away leaves with them.

- **A first-visit note tells a newcomer the index exists.** The `index.md` an
  author wrote to be read first was reachable only by finding the Indexes tab and
  clicking a row, so a reader meeting a bundle for the first time met unlabelled
  dots with no way in. The page still opens on the graph — it is what makes a
  bundle legible at a glance, at every width — and a dismissible note at the
  bottom now says what the picture is, how to touch it, and where the index is.
  **Read the index** goes straight there; the dismissal is remembered.
  - **It absorbed the old mobile-only tip** rather than stacking a second banner
    under it, and it is written for a finger throughout, since a phone is where a
    first-time reader is least oriented.
  - **The wording follows the device on two gates, not one.** What a reader does
    follows `(pointer:coarse)` — a touch tablet in landscape is wider than 768px
    and still taps; a narrow desktop window is narrower and still clicks. What a
    reader can reach follows `(max-width:768px)`, because that is when the rail
    collapses behind `☰`. Short viewports tighten; short *and* wide puts the
    question beside the button, taking a landscape phone from half the screen to
    under a third.
  - **A second note points at `☰`** on compact layouts only, anchored under the
    button it names rather than at the bottom of the screen. It fires on leaving
    the graph by any route, so dismissing the first note does not cost it, and
    opening `☰` answers it — but only once it is on screen, since `☰` is the only
    way off the graph there and the first tap always comes first.
  - **Deep links are unaffected**, and `?select=`/`#hash` now switch to the graph
    before selecting, since the page can be standing elsewhere when they are read.

- The graph page's search box grows a full-text index. One MiniSearch index —
  lazy-loaded from the CDN on first search, pinned to the `7.2.0` the Ruby
  MiniSearch port tracks so an `okf search --engine index` result and the
  browser's rank identically — now backs the graph, catalog and files views: ranked, multi-term
  (`AND`), prefix (as-you-type) and typo-tolerant, over title, id, type, tags and
  **description** — plus each concept's **body** wherever the page already holds
  it (`okf render` bakes every body in, so a static file searches bodies offline;
  the live server keeps bodies lazy, so its index stays metadata-only until a
  backend body index arrives). The graph could not be searched by a leaf's
  description before; now it can. The Files view's **Indexes** tab gets its own
  full-text index too, over each `index.md`/`log.md`'s body — not just its
  filename. Until an index loads — or if the CDN is unreachable — each view falls
  back to its own substring filter, so the box is never dead.

- `Esc` clears the graph selection. A dense graph leaves almost no empty canvas
  to click for deselecting; `Esc` now drops the highlight (and lets the URL hash
  forget the node) the same way tapping empty canvas does.

### Changed

- **The default search is unchanged** — literal, case-insensitive substring
  matching over the same fields with the same weights as 1.8.0. The index is
  opt-in rather than default because a one-shot CLI builds an index, asks one
  question, and exits: end to end, **3.00 s against 0.24 s at 1,000 concepts**,
  the build accounting for ~95% of that. The ~44–56× per-query throughput that
  recommends minifts is the right measure for a long-lived index — a page, a
  server — and the wrong one for a process that exits. A cached prebuilt index is
  what would change that arithmetic.
  - **Know what the index costs before naming it.** Its tokenizer splits on
    punctuation, so `customer_id` becomes `customer` + `id` and `7.2.0` becomes
    `7`, `2`, `0`; an infix (`ustomer`) finds nothing; and a backtick is Unicode
    `Sk` rather than punctuation, so a word inside a code span indexes as
    `` `minifts` `` and the query `minifts` does not match it — 409 such tokens
    on this repo's own bundle. Ranking does not rescue it: BM25 normalizes by
    field length, so a short concept dense in `7`, `2` and `0` can outrank the one
    that actually says `7.2.0`. The default has none of these, because raw-text
    matching has no tokenizer.

- **Search engines are adapters.** `OKF::Bundle::Search` became a facade over N
  engines instead of one class with a `regexp ? scan : index` branch. The facade
  keeps everything that defines a result — documents, the row and its key order,
  the snippet, the sort — and an engine answers only which documents match, how
  well, and where. The built-ins are `Search::Scan` (raw text, the default,
  `regexp`) and `Search::Index` (minifts, `fuzzy`/`prefix`).
  - **Selection is by capability when the query requires one** — `--fuzzy`
    requires `:fuzzy`, so it routes to the index without naming it — and that
    routing prints **nothing**: no note, no header change, no new JSON key.
  - **`Search.register` is a published extension point** — append-only,
    idempotent by id, capabilities checked against a fixed vocabulary. This is
    the seam a future SQLite/FTS5 addon plugs into; no addon code ships here.
  - **A shared conformance suite replaces the "kernel is the oracle" rule**,
    which multiple engines made impossible: the index and the scan disagree about
    match sets by design, so neither can be the oracle. Every registered engine
    runs the same contract, with capability-gated blocks for its own semantics,
    and a registered engine with no conformance class fails the suite.

- **Cross-bundle search ranks one corpus under `--engine index`.** BM25 prices a
  term by how rare it is, so ranking each bundle separately and interleaving the
  lists would produce a ranking that looks sorted and compares nothing; the
  searched bundles are indexed together instead. The visible consequence, under
  that engine only: a score is relative to the whole answer, so the same concept
  scores lower searched beside other bundles than alone. The default's scores are
  absolute and need no such treatment.

- **Collapsing the root folds the file list away** on phones and tablets, where
  the list is stacked on top of the reader and closing the root otherwise left a
  single row above a column of nothing. Reopening the list undoes that collapse,
  so it is one gesture rather than two states to dig out of — the fold remembers
  *why* it happened, and a list folded because a file was opened comes back
  exactly as it was left.

- **The bundle names its own root.** `(root)` and `/` are what a filesystem calls
  it, not what a reader does. The tree's root row, file-tree mode's root node, the
  index layer's root map and the inspector's directory map now all carry the name
  the page header already shows, `--title` included. `areaOf` keeps its own
  `(root)`: that is the area vocabulary `okf stats --by area` and `tags --by area`
  print, not a UI label.

- **The Indexes tab dissolves into the file tree.** The authored layer lived on a
  second tab as a flat list of paths, which put a directory's own map somewhere
  other than the directory. `index.md` and `log.md` are rows now, at the top of
  the folder they document, and **Indexes only** is a toggle over the same tree —
  same rows, fewer of them, structure intact. The toggle yields only when it would
  hide what was just opened — a map stays under it, a concept releases it — so
  browsing the authored layer no longer destroys the list being browsed. A log
  offers no graph button at all: it is a chronology, not a place in the graph, and
  the button had been opening the root index's node.
  Narrowed, a folder owns exactly one row, so the row stands where the folder
  header stood — at that folder's depth, carrying the path — rather than nesting
  a single child under a header.
  - **The rail's Index becomes an action, not a fake view.** It had no
    `#view-index` behind it — the files view showing its other tab — so
    `activeRail()` answered a question of view *and* tab. The shortcut stays,
    opening the root map through the same `readIndex()` the first-visit note
    uses; `activeRail()` answers with the view it lands on, so Files highlights
    and nothing invents a place for Index to be. `?view=index` resolves to the
    same action.
  - **Fixed on the way:** the reader header rendered empty — an unlabelled badge
    and a graph button pointing nowhere — whenever no file was open, because
    `.fp-head{display:flex}` outranks the UA sheet's `[hidden]{display:none}`.

- **The file tree nests.** Directories were a sorted list of full paths, which
  made `core` and `core/configurations` read as two unrelated folders and left
  the shape of a bundle invisible. Each row is now one path segment indented by
  depth, folders before files, and collapsing a folder takes its subtree with it.
  A directory holding nothing but directories still renders, so the chain to its
  children never breaks.
  - **"Collapse all" folds into the root, not over it** — everything inside the
    root closes and the root stays open, so the click leaves the top-level
    folders standing instead of a single `(root)` row. Unfolding clears the whole
    set, root included, so a root closed by hand is still reversible from there.

- `okf render` stops baking a redundant description map. The static page derived
  its `/node/meta` fragments from a separate `meta` payload that held nothing but
  each concept's description, HTML-escaped — data the embedded `catalog` already
  carries raw. The page now escapes the catalog's description on the client (the
  same escape the server applies at `/node/meta`), so the `meta` key leaves the
  baked payload and the description lives in one place. Both XSS guards are
  unchanged; `okf server` is untouched.

- The bare not-a-directory error now teaches the registry grammar. A verb given
  a target that is neither a directory nor an `@ref` moved from
  `error: <arg> is not a directory` to
  `… is not a directory or a registry ref (@slug names a registered bundle, @ the default; okf registry list)`,
  so a consumer who typed a query or a bad path meets `@slug` addressing at the
  error instead of hunting for it. (`@all` stays out of the message — it is
  `search`'s alone, and the error seam is shared by every verb.)

- The bundled skill teaches `@slug` as a first-class target and stops probing for
  the CLI. `SKILL.md`'s "Which directory?" is now "Which target?" — a leading `@`
  is a registry ref routed straight to `okf <verb> @slug`, with the fallback
  "no bundle in the cwd → `okf registry list`" — and the consume/search playbooks
  name `@slug` in their orientation steps. The per-run `command -v okf` presence
  probe is gone: run the verb, and treat a shell `command not found` as the only
  signal to install, so the common case pays no guard round.

### Fixed

- The Files tree's folder collapse works during a search. An active search or
  type/tag filter used to force every folder open, so fold clicks did nothing;
  folders now honor their collapsed state always (a collapsed group still shows
  its header, so a match is never hidden). A **fold/unfold-all** control in the
  Files tab header collapses or expands every visible group at once.

- Clustering no longer leaves phantom empty boxes. When a filter or a search hid
  every concept in an area, the cluster's labelled box lingered as an empty
  rectangle; the box now hides when no child survives and returns when one does —
  the same rule the fit already used to leave stale boxes out of view, now
  applied to what is drawn.

- A title-less concept now wears one name in every view. `catalog` and the §6
  index listing fell back a concept with no `title` to its full id — `area/thing`
  — while the graph node fell back blank-aware to the basename — `thing` — so the
  same concept answered to two labels across two views of one bundle, and a
  `title: ""` slipped past the nil-only `||` to catalog as an empty string. Both
  now fall back the graph's way (`File.basename`, blank-aware), so the label is
  the same wherever the concept appears.

## [1.8.0] - 2026-07-17

### Added

- A persistent bundle registry and a multi-bundle hub. `okf registry`
  (list / set / del / default / rename) keeps a per-user list in a plain JSON
  file at `$OKF_HOME/registry.json` (default `~/.okf`), and `okf server` reads
  its mode from its arguments: one dir is the classic single bundle at `/`,
  several mount ephemerally behind a hub at `/b/<slug>/`, none serves the whole
  registry with its default at `/`. Behind a hub the page gains a bundle
  switcher (⌘/Ctrl-K, or the rail button), `/b/` is a browsable index, and an
  unknown slug 404s as a page with a way home. The hub reads its bundles at
  boot — restart after registry changes.

- The registry is **ordered, and the first entry still on disk is the default** —
  the bundle a bare `okf server` opens at `/`. `okf registry default @slug` moves
  that entry to the front, and `okf registry set --default` registers straight to
  it; until you do either, the first bundle you registered is the default. Nothing
  else has to be maintained: a rename keeps its position, a `del` promotes
  whatever is next, and the file cannot name a default that is not there. A
  vanished directory is stepped over rather than starred — `registry list`'s `*`
  always names the bundle `/` opens — and `registry default @slug` refuses one,
  just as `registry set` refuses to register a directory that is not there.

- `$OKF_HOME` is the single lever on which registry a command reads: set it and
  every verb follows, from `okf registry list` to an `@slug` on `okf lint`. It
  names exactly one registry, with no fallback to `~/.okf` behind it, and an
  empty value counts as unset rather than planting `registry.json` in the
  current directory.

- `@slug`: wherever a command takes a `<dir>`, `@slug` names a registered
  bundle and bare `@` the registry default — `okf lint @handbook`,
  `okf render @ -o graph.html`. A slug is normalized like registration was
  (`@One` finds the bundle from dir `One`) but never to a placeholder, so
  `@***` is a bad ref rather than a silent hit. An unknown slug, a
  registered-but-gone directory, or a malformed registry file is a usage error
  naming the registry file and the next move. A hub built from `@slug`s
  (`okf server @a @b`) mounts each bundle under its registered slug, the first
  at `/`, and a registered slug reserves its mount ahead of any plain
  directory that shares the name.

- `okf search` spans bundles: several leading `@slug`s, or `@all` for every
  registered one. Rankings merge across bundles with every row labeled by its
  bundle's slug (a `bundles` list and a per-match `slug` key in the JSON).
  Asking for everything tolerates gaps — `@all` skips a bundle whose directory
  has vanished, with a note — while naming one insists on it, and `@all @docs`
  simply dedupes. `all` is reserved *in the registry*, on all three ways in: a
  directory named `all/` registers as `all-2`, `--as all` is refused, and a row
  already claiming the name in the registry file — hand-typed, or written before
  the name was reserved — is read as `all-2`, so the reservation never strands a
  registry it inherited. An ephemeral `okf server ./all` still mounts at
  `/b/all/` — no registry, no refs, nothing to reserve.

- The inspector's type and tags are filter handles: clicking one focuses the
  graph on that facet — the same jump the stats bars make — and clicking it again
  clears it. The chip lights while its facet is the only filter in play, which is
  exactly when a second click is an undo, so what you see and what the next click
  does are the same question. With another filter set it re-focuses instead,
  rather than throwing away more than the click put there.

- The graph page answers `?` with a sheet of every keyboard shortcut, reachable
  from a rail button too — a shortcut list you can only open with a shortcut helps
  whoever needs it least. `/` focuses the current view's search where it has one,
  skipping the view that only reads; the sheet is written against the key handler
  it documents, since a shortcut list that has drifted is worse than none.

### Changed

- `@slug` is spelled where it is used, not just where it is explained, and it is
  the one token — `okf help`'s map (`lint <dir|@slug>`) and each command's own
  banner show it the same way, with a note under the map defining it: the slug
  from `okf registry set`, or bare `@` for the default. It was documented once,
  in prose at the foot of `okf help`, past where a reader who already knows the
  verb ever looks, so seventeen surfaces took a registered bundle while
  advertising a bare `<dir>`. The registry-editing verbs — `del`, `default`,
  `rename` — take the slug bare (no `@`) or as an `@slug`; the read verbs need
  the `@`, since a bare word there is a path.

- `okf <command> -h` prints that command's own banner and flags. Help now answers
  on stdout with an exit code like every other command: it was OptionParser's
  officious handler, which printed past the caller's injected streams and ended
  the process with `exit` instead of returning a status.

- The registry validates its file's shape, not just its JSON syntax: a
  hand-edited entry missing `path` is a usage error naming the file instead of
  a `TypeError`, and `okf registry --json set <dir>` — a subcommand behind a
  flag — is a usage error rather than silently listing and exiting 0.

- The graph page's ⌘/Ctrl-K palette opens in **every** mode and reaches a view as
  well as a bundle. It was wired only behind a hub, so a standalone
  `okf server ./docs` and every `okf render` page — the two modes most people meet
  first — had no palette at all. Bundles still lead it and own the empty box,
  because switching bundles is what it is for; views wait until what you type
  reaches one, arrive underneath, and stay muted until the cursor does. Each view
  carries the rail's own icon and label, read from the rail so the two cannot
  drift. Where there is no hub there is no bundle to switch to, and views become
  the whole list.

- The inspector's *Links to* / *Linked from* rows read as concepts rather than a
  wall of accent-coloured text. Each carries its type's dot — the colour that node
  already wears in the graph beside it — with the type named and the section
  counted, so the column answers what kind of neighbourhood a concept has before a
  title is read. The rows share one panel with hairline dividers and a hover fill:
  the container carries the click affordance, which leaves colour free to mean type
  and nothing else.

- The inspector's widen chevron splits the screen instead of taking 70% of it. The
  panel drag-resizes, so the chevron is a preset rather than a maximum, and burying
  the graph to read one concept was the wrong thing to default to.

### Fixed

- A file the reader could not **open** (permissions) threw its errno out
  of the read, so a single locked file took the whole bundle down through every
  verb that reads one — `lint`, `validate`, `catalog`, `server`, `registry set`
  — as a backtrace, under an exit code claiming the bundle was non-conformant.
  §9's best-effort promise covers it now, the same as frontmatter that will not
  parse: the file is skipped, noted on stderr, and reported by `validate` under
  §9.1 naming the file and the errno. One bad file never breaks the rest.
  The stderr note reads `skipped N unusable file(s)` — it counts two kinds now,
  so it names neither and points at `validate`, which names both.

- `okf registry del <path>` could delete the wrong bundle. A path that
  matched no registered directory fell through to a normalized *slug* lookup, so
  `del ./notes` — naming a local directory — removed whichever entry happened to
  be slugged `notes`, wherever it pointed, and reported `removed notes` with exit
  0. An argument with a `/` in it now names a location and only a location.

- The registry read trusted stored slugs verbatim while both write paths
  normalized, so a hand-typed `"slug": "My Docs"` listed fine but could not be
  named by `@my-docs`, `registry rename`, or `registry default` — the verbs that
  could repair it were the ones that could not see it. The read normalizes now,
  leaving an already-usable slug untouched. This also removes the only way a
  quote could reach a slug, and with it a DOM XSS in the server's bundle
  switcher, whose JS escape covered `& < >` but not quotes; the escape now covers
  quotes too, so the page does not depend on a guarantee three layers away.

- `okf lint` bucketed a whitespace-only `type` under its own literal
  heading while `types`/`graph`/`stats` bucketed it as `Untyped`, so two verbs
  reported type inventories for the same bundle that would not reconcile. §9.2
  makes a blank type as non-conformant as a missing one; both sides say so now.

- `okf search <dir> --fields slug` passed the field guard and returned one
  empty object per match with exit 0. Only registry mode labels rows with a slug,
  so the two modes now declare the shape each actually emits and a path-named
  search names the fields it does have.

- `okf registry set` reported `(0 concepts)` for a bundle whose files it
  could not read; it notes the skipped files like every other reading verb.
  `okf registry rename DOCS handbook` echoed the argv rather than the slug it
  renamed, naming a bundle that never existed. An unwritable `$OKF_HOME` raised
  a bare `Errno::EACCES` at exit 1 instead of a usage error at exit 2.

- A long path in the Files view's Indexes tab pushed its `map`/`log` badge
  past the right edge of the list. The badge was already pinned and unshrinkable;
  the filename beside it was the problem — a bare text node, and an anonymous flex
  item's automatic minimum size is the full width of its text, so it refused to
  give way and drove the badge out instead. It truncates now, with the full path on
  hover. Only a wide enough path in a narrow enough pane reached it, which is why
  it never showed on mobile, where the list runs full width.

- The bundle switcher scrolled its own first row out of view as it opened.
  It rendered, and scrolled the active row into view, while the dialog was still
  hidden — and a list that is not being displayed measures zero, so the scroll
  landed arbitrarily.

- The `3` (Files) shortcut did nothing once the Indexes tab was open, and
  the palette's Index row would have blanked the page. "Index" is not a view —
  there is no `#view-index`, only the Files view showing its Indexes tab — so
  `setView('files')` from that tab early-returned, and `setView('index')` named a
  view that does not exist. The keyboard and the palette each re-implemented what
  the rail button already did right; both now click the rail item, so the one
  correct path is the only one, and the palette's `current` badge reads the same
  active-tab answer the rail's own highlight does.

## [1.7.0] - 2026-07-16

### Added

- `okf server`: responses are gzipped when the client accepts it
  (`Rack::Deflater` at the boot seam). Lossless and transparent — the browser
  decompresses automatically — and no new dependency, since `Rack::Deflater`
  ships inside rack. Clients that send no `Accept-Encoding` keep getting
  identity responses. `okf render`'s static HTML is untouched.

- The agent skill gains a `migrate` verb (`playbooks/migrate.md`): convert
  existing documentation into a conformant bundle **in place** — frontmatter
  and reserved files added, bodies kept verbatim (`produce` keeps
  distillation). The verb is routed from SKILL.md's Commands table and intent
  inference, the menu playbook now leads with it when a target already holds
  markdown docs, and pointing any verb at a directory that is not a bundle now
  suggests `migrate` instead of grinding through the validate errors.

### Changed

- The graph page's link-preview image points at the renamed
  `okfgem.com/og-demo-v3.png`. The site's OG art was refreshed to drop "Live
  Graph" from the package formula (it is `Agent Skill + CLI/Lib + Graph` now
  that `okf render` makes the graph live *or* static), and the filename carries
  the version so social scrapers pick the new art up.

- The plugin's `/okf:gem` command is now a pass-through shim: it hands its
  arguments to the okf skill unchanged, making `SKILL.md` the single router
  for every channel. The routing prose the command used to duplicate had no
  drift guard (the sync test covers only the generated skill copy), and the
  not-a-bundle `migrate` suggestion now lives in `SKILL.md`, so standalone
  skill installs get it too.

## [1.6.0] - 2026-07-15

### Added

- New CLI verb: `okf render <dir> [-o FILE]` — the live graph as one static,
  self-contained HTML file, so it hosts where a server can't (GitHub Pages, an
  object store, an attachment). It is the same page `okf server` serves, one
  switch apart: the browser's five on-demand reads — bodies, descriptions,
  catalog, index, logs — now route through named getters that resolve from an
  injected `EMBED` payload instead of the network, so the whole bundle rides
  inside the file with no server and no build step. Prints to stdout (`okf
  render docs > public/index.html`) or writes `-o FILE`. The embedded data is
  `</script>`-escaped exactly like the boot payload and every body still renders
  through `DOMPurify.sanitize(marked.parse(...))`, so the trust boundary holds;
  the trade-off is weight — each body is inlined, so a big bundle makes a big
  file, and `okf server` stays the choice at scale.

- Official Docker image: `ghcr.io/serradura/okf`, a portable CLI that runs every
  `okf` command (the graph server included) with no Ruby on the host. It is built
  from source and published multi-arch (`linux/amd64`, `linux/arm64`) to the
  GitHub Container Registry on each release tag, so the image always matches the
  gem. Mount a bundle at `/data`; for `server`, add `--bind 0.0.0.0` and publish
  `-p 8808:8808`. See the README's Docker section.

## [1.5.0] - 2026-07-13

### Added

- New CLI verb: `okf search <dir> <term…>` — deterministic ranked retrieval
  over concept metadata *and bodies*, the browser page's search brought to the
  CLI. Terms AND together as case-insensitive substrings, or as Ruby regexps
  with `--regexp`/`-e`; `--in` restricts the searched fields; the shared
  `--type/--area/--tag` filters and `--fields/--except` projections apply.
  Matches rank by where they hit (title > id > tags > type/description > body)
  and carry a bounded context snippet, so "which concept covers X?" costs a
  few rows instead of a body read. Advisory read: exit 0 even with no matches.
  Deliberately not fuzzy — the consuming agent is the fuzzy layer.

- The skill learns retrieval as a first-class verb: a new `search` playbook
  (progressive disclosure end to end: ingest `okf index`, decide where to
  look, cut across with `okf search`, read only the winning bodies),
  search-aware routing in SKILL.md and the menu/consume playbooks, and
  `/okf:gem search <query>` first in the Claude Code plugin's routing.

- Retrieval eval in the suite: the progressive path (index skeleton → search →
  one body) must answer a planted question in under 25% of the bytes of the
  full graph dump, so the playbook's economics stay true by construction.

- Graph server: the authored layer joins the UI. The Files view carries two
  tabs — **Files** (the per-directory concept groups, foldable) and
  **Indexes** (the log first, as the chronological index, then every
  `index.md`, root before nested) — with the files filters moved up into the
  top bar. The rail's **Index** item, the `2` key, and `?view=index` are
  shortcuts straight to the Indexes tab. Folder nodes in file-tree mode and
  area boxes in cluster mode are clickable and open that directory's §6 map
  in the inspector (authored, or the synthesized listing when none exists).
  Links to an `index.md`, a `log.md`, or a bare directory (`model/`) navigate
  everywhere a body renders instead of striking through as dead, and the log
  is fetched fresh on every read, so a just-appended entry shows without a
  restart. A reserved file's "Open in graph" jumps to its folder in the file
  tree, map in the inspector. New `/index` and `/log` endpoints back it all.

- Graph server: Mermaid diagrams in concept bodies are click-to-inspect. A
  click (or tap) opens the diagram full screen — drag to pan, wheel or pinch
  to zoom, buttons and double-click reset, Esc closes — powered by
  [Panzoom](https://github.com/timmywil/panzoom), lazy-loaded from the CDN
  exactly like Mermaid itself.

### Changed

- The Claude Code plugin's `/okf:gem` command now weighs the shape of a
  free-form ask: a question about what the bundle knows routes through the
  search playbook and answers from retrieved concepts instead of guessing.

- Skill efficiency audit: every playbook now takes the CLI's lean paths.
  `maintain` hunts affected concepts with `okf search` and pulls edges via
  `graph --json --minimal` instead of the full-body dump, `menu` reads the
  plain-text reports it only scans, and SKILL.md pins the discipline as a
  rule: skeleton first, bodies last.

### Fixed

- Docs: the CLI reference's server section now reflects the DOMPurify
  sanitization that landed in 1.1.0 (it still said bodies render unsanitized),
  and the server page's link-preview image points at the renamed
  `okfgem.com/og-demo-v2.png`.

## [1.4.0] - 2026-07-12

### Changed

- Graph server UX round. Selecting a node now makes one camera move instead of
  two (the pan used to race the opening panel and the debounced canvas resize,
  a dizzying double movement; rapid clicks also queued animations — both fixed).
  Relative markdown links inside the inspector and the files preview resolve
  against the open concept and navigate in-app — clicking `../model/graph.md`
  selects that concept instead of 404ing the page; external links open in a new
  tab; links that leave the bundle are disabled, never a 404. Nodes are smaller
  (14–44px, was 24–70) and layouts keep a real gap between them (`nodeOverlap`
  for cose, `avoidOverlap`/`spacingFactor` elsewhere). The inspector and the
  files list are drag-resizable (persisted, double-click resets), and the files
  reader now uses the full pane width. New file-tree mode on the graph toolbar:
  folders become nodes and the only edges are folder→child, an acyclic layered
  tree of the bundle's files. On small screens (≤900px) the inspector starts
  hidden and opens on the first node tap; camera moves are gentler (450ms,
  ease-in-out).

## [1.3.0] - 2026-07-12

### Added

- The graph server page now emits link-preview metadata: Open Graph and Twitter
  Card tags with a social image, plus `theme-color` and `color-scheme`, so a
  shared `okf server` URL unfurls as a proper card in chat and social apps.

- Docs: a themed README hero (light and dark), a GitHub social preview image,
  and Website / Live demo / Claude Code plugin links.

## [1.2.0] - 2026-07-12

### Added

- Claude Code plugin. The repository now doubles as a plugin marketplace:
  `/plugin marketplace add serradura/okf-gem`, then `/plugin install okf@okfgem`.
  The plugin carries the canonical skill (a generated copy; `rake plugin:sync`
  keeps it in lockstep with `lib/okf/skill`, and a test fails on drift), one
  front-door command (`/okf:gem`: no arguments orients on the CLI, the bundle,
  and what `validate`/`lint` report and recommends the highest-value next move
  without running one, `doctor` installs the gem and doctors the repo's bundle,
  `curate` runs the full validate + lint + loose cycle, anything else hands the
  task to the skill), and a PostToolUse hook that runs `okf validate` +
  `okf lint` after every edit inside a bundle and hands the relevant findings
  back as context: every conformance error, plus the warnings and lint findings
  that concern the edited file. The checks are the CLI's own, so the feedback is
  deterministic. The hook stays silent outside bundles, and when the CLI is
  missing it suggests `/okf:gem` once per session instead of erroring on each
  edit. It is config-free to silence: `OKF_CURATE_DISABLED=1` turns it off,
  `OKF_CURATE_QUIET=1` keeps the findings but drops that suggestion, and an
  `<!-- okf-disable -->` comment in a file skips curation for that one. The skill
  routes through per-verb playbooks (`playbooks/`), and its signature guidance
  lines carry stable `<!-- check:… -->` / `<!-- rule:okf-… -->` markers.
  Nothing under `plugin/` ships in the gem.

## [1.1.0] - 2026-07-12

### Changed

- `require "okf"` now loads the pure library only. The two argv-facing shells —
  `OKF::CLI` and the `OKF::Skill` installer — load on demand, from `exe/okf` or
  an explicit `require "okf/cli"` / `require "okf/skill"`. `optparse` moves with
  the CLI, so an embedding app (e.g. a Rails store) that only reaches for the
  in-memory model and on-disk handles no longer pulls in the command-line
  machinery. The CLI itself is unchanged.

### Security

- The graph server now sanitizes every concept body before rendering it. The
  page runs marked's HTML output through [DOMPurify](https://github.com/cure53/DOMPurify)
  (loaded from the same CDN as Cytoscape and marked) on the way to the DOM, so a
  bundle carrying active content in a Markdown body can no longer script the
  viewer. Inlined graph data was already escaped through `json_for_script`; this
  closes the other path.

## [1.0.0] - 2026-07-12

Initial release.

### Added

- `OKF::Concept` / `OKF::Bundle`: pure in-memory model of an OKF v0.1 bundle,
  buildable straight from data (no disk) with link, citation, and markdown
  round-trip primitives.

- `OKF::Bundle::Validator`: the spec §9 conformance gate (hard errors) with the
  spec's soft guidance reported as warnings — broken cross-links are tolerated,
  as §5.3 requires.

- `OKF::Bundle::Linter`: advisory curation-quality report across reachability,
  backlog, completeness, freshness, provenance, and hygiene, with `--json` as a
  machine substrate.

- `OKF::Bundle::Graph`: the knowledge graph (nodes, edges, type/tag indexes) at
  selectable fidelity.

- On-disk handles: `OKF::Bundle::Folder`, `OKF::Bundle::Reader`,
  `OKF::Bundle::Writer` (atomic, validate-before-publish), and
  `OKF::Concept::File`.

- `OKF::Server::App`: the interactive graph as a mountable Rack app — five views
  (graph, catalog, files, tags, stats) with type/area/tag filtering throughout,
  bodies fetched live from disk — served by a built-in WEBrick runner
  (`okf server`).

- `okf` CLI: `validate`, `lint`, `loose`, and `graph`, plus the read views as
  text — `index`, `catalog`, `files`, `tags`, `types`, `stats` — at full parity
  with the browser: every list view narrows with `--type`/`--area`/`--tag`
  (case-insensitive; the bundle root is area `(root)`, accepted as `root`), and
  `tags --by type|area` regroups the tag index per concept dimension with
  within-group counts — the tag-curation view. `server` boots the graph page;
  `skill` installs the companion skill.

- `okf index`: a read view over the progressive-disclosure layer (spec §6) — one
  entry per directory that holds concepts or carries an `index.md`, root first,
  with its authored index body (frontmatter stripped), a type/tag rollup over the
  concepts that live there, its child directories, and the concept listing. A
  directory with concepts but no `index.md` has its listing synthesized (§6 permits
  it) and is flagged. `--area` (repeatable), `--no-body`, and `--json`; advisory,
  always exit 0. Backed by the pure `OKF::Bundle#directory_index`.

- JSON output is **compact by default** across every emitting verb (the
  token-efficient machine substrate, matching the server); `--pretty` indents it
  for reading and implies `--json`. JSON semantics are identical either way — only
  whitespace differs — so any parser is unaffected.

- JSON property projection on the list views: `index`, `catalog`, and `files`
  take `--fields a,b` (emit only these properties) or `--except a,b` (emit all but
  these), so an agent never pays tokens for fields it will not read. The flags are
  mutually exclusive, imply `--json`, match property names case-insensitively, and
  reject an unknown name (exit 2) listing the valid ones; `okf index --no-body` is
  shorthand for dropping the `body` field.

- Bundled companion agent skill (`okf skill <dest>`): SKILL.md carrying the
  judgment (the CLI surface stays self-describing via `--help`) — including the
  orient-before-you-read protocol and the CLI/judgment boundary — the OKF v0.1
  spec, authoring and CLI references (tag-vocabulary curation, the SPEC-section
  map, the closeout gate), and concept/index/log templates.

- Runs on Ruby >= 2.4 with two runtime dependencies: rack and webrick.

[1.10.0]: https://github.com/serradura/okf-gem/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/serradura/okf-gem/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/serradura/okf-gem/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/serradura/okf-gem/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/serradura/okf-gem/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/serradura/okf-gem/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/serradura/okf-gem/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/serradura/okf-gem/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/serradura/okf-gem/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/serradura/okf-gem/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/serradura/okf-gem/releases/tag/v1.0.0
