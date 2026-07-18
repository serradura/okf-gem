# Changelog

## [Unreleased]

- **The graph can draw the index layer, under any layout.** The §6 map was
  visible only inside file-tree mode, where a folder node stood in for a
  directory's `index.md`. **Show indexes** makes it a layer: each map is a tile
  edged to the concepts it lists and the maps below it, dressed by the same
  selector as file-tree mode's folder node for everything structural — square,
  small type, never a concept's circle — and parting from it on colour: the file
  tree draws structure and stays grey, the index layer draws the authored map and
  takes the accent. Authorship then shows as form: solid where an author wrote a
  map, hollow and dashed where the bundle only implies one, so the toggle reads as
  curation as much as navigation.
  - **Moving between the modes lands in one click.** Tearing the layer down ran
    its own layout while file-tree mode ran `breadthfirst` a beat later, two
    layouts racing the same canvas; and because the layer is fetched, a promise
    resolving after a mode change could land inside file-tree mode. A `relayout`
    flag settles the first, a per-toggle ticket the second. File-tree mode disables it rather than
  doubling the folders it already draws.
  - **Drawn, never modelled.** `index.md` is reserved, so these nodes are built
    from `/index` straight onto the canvas; `NODES`, `/catalog` and the type and
    tag indexes never learn they exist. Filters pass them over — a map has no type
    or tags — but a map whose concepts are all filtered away leaves with them.
- **Collapsing the root folds the file list away** on phones and tablets, where
  the list is stacked on top of the reader and closing the root otherwise left a
  single row above a column of nothing. Reopening the list undoes that collapse,
  so it is one gesture rather than two states to dig out of — the fold remembers
  *why* it happened, and a list folded because a file was opened comes back
  exactly as it was left.
- **The Indexes tab dissolves into the file tree.** The authored layer lived on a
  second tab as a flat list of paths, which put a directory's own map somewhere
  other than the directory. `index.md` and `log.md` are rows now, at the top of
  the folder they document, and **Indexes only** is a toggle over the same tree —
  same rows, fewer of them, structure intact. Opening a reserved file releases it.
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

- **`okf search --engine NAME` picks the engine outright.** Capability flags
  select an engine when the query *requires* something (`-e` needs `:regexp`,
  `--fuzzy` needs `:fuzzy`), but raw-text matching requires nothing, so no flag
  could ask for it. `--engine scan` is that ask: the pre-index behaviour, with
  phrases, infixes, dotted identifiers and code spans all matching, at the cost
  of BM25 ranking. Naming an engine that cannot do what was also asked is a usage
  error that names one that can (`--engine index -e` → *try --engine scan*), and
  an unknown name lists what is available. `--help` reads the registry, so an
  addon's engine appears without the CLI knowing it exists.
- **The scan matches literally unless `-e` says otherwise.** It compiled every
  term as a regexp, which was invisible while `-e` was the only way to reach it.
  With `--engine scan` it would have meant `7.2.0` matching `7x2y0`, `[draft]`
  acting as a character class, and an ordinary term like `review (pending`
  failing as an invalid pattern. Terms are now escaped unless `--regexp` is
  given, so the engine chooses *where* to match and `-e` chooses *how*.
- **Known recall gap, now documented and recoverable.** A backtick is Unicode
  `Sk`, not punctuation, so MiniSearch's tokenizer never splits it off: a word
  inside a code span indexes as `` `minifts` `` and the query `minifts` does not
  match it. On this repo's own bundle that is 409 tokens over 1,013 occurrences —
  `okf search .okf minifts` finds 2 concepts where `--engine scan` finds 5. The
  scan recovers it; the default still misses it.
- **Search engines are adapters now.** `OKF::Bundle::Search` became a facade over
  N engines instead of one class with a `regexp ? scan : index` ternary. The
  facade keeps everything that defines a result — documents, the row and its key
  order, the snippet, the sort — and an engine answers only which documents match,
  how well, and where. The two built-ins are `Search::Index` (BM25+, default) and
  `Search::Scan` (regexp).
  - **Selection is by capability when the query requires one.** `-e` requires
    `:regexp`, `--fuzzy` requires `:fuzzy`, anything else gets the default — and
    that routing prints **nothing**: no note, no header change, no new JSON key.
    Every pre-existing invocation answers exactly as before. (`--engine`, above,
    covers the case where nothing is required but the matching model matters.)
  - **`okf search --help` tells the engine story**, since routing itself is
    silent: each capability flag names its engine, `--engine` lists the
    registered ones, and a note states the token/raw-text split with examples.
  - **`Search.register` is a published extension point** — append-only,
    idempotent by id, capabilities checked against a fixed vocabulary. This is
    the seam a future SQLite/FTS5 addon plugs into; no addon code ships here.
  - **A shared conformance suite replaces the "kernel is the oracle" rule**,
    which multiple engines made impossible: the index and the scan disagree about
    match sets by design, so neither can be the oracle. Every registered engine
    now runs the same contract, with capability-gated blocks for its own
    semantics, and a registered engine with no conformance class fails the suite.
  - **The precision the token index gives up is pinned from both sides** — phrase,
    dotted version, underscored identifier, infix — each asserting the false
    positive the index admits *and* that `-e` refuses it. Writing those tests
    falsified the claim that ranking keeps the true hit first: it does not. On
    this repo's own bundle, `okf search .okf 7.2.0` ranks the Ruby-floor concept
    above the one that names the version. The docs claiming otherwise are
    corrected.
- **`okf search` runs on a full-text index.** The engine is now
  [minifts](https://github.com/serradura/minifts) — the pure-Ruby port of the
  same MiniSearch build the browser page loads — making it the gem's third
  runtime dependency (still no native extension, no dependency tree of its own,
  same Ruby 2.4 floor). The CLI and the browser are one engine now, so they rank
  identically instead of agreeing by maintenance. What changes for callers:
  - terms match **tokens** and the tokens they prefix (`dedup` finds
    `deduplication`) rather than raw substrings, so a mid-word fragment
    (`ustomer`) no longer matches — use `-e` for that;
  - ranking is **BM25+**, with the old per-field weights riding as boost, so
    scores are floats and orderings shift;
  - `--fuzzy` opts into typo tolerance (edit distance `0.2 × term length`, the
    browser's setting). Search stays exact by default;
  - `-e`/`--regexp` still runs a linear scan — a pattern is the one query an
    inverted index cannot answer — and pairing it with `--fuzzy` is a usage
    error (exit `2`) rather than a silently ignored flag;
  - rows still carry `matched`, the fields each term hit, so a result stays
    citable rather than being a bare relevance number.
- **Cross-bundle search ranks one corpus.** `okf search @a @b` used to rank each
  bundle separately and interleave the lists, which was sound when scores were
  absolute field weights and became wrong under BM25, where a term is priced by
  how rare it is in the corpus. The searched bundles are now indexed together, so
  the merged ranking is comparable by construction. A visible consequence: a
  score is relative to the whole answer, so the same concept scores lower
  searched beside other bundles than searched alone.
- **Known cost:** the index is built per invocation, so a one-shot CLI search now
  pays for a build it never amortizes — ~55 ms on a 23-concept bundle (against
  ~2 ms for the old scan), ~2.2 s at 1,000 concepts. Negligible at the size real
  bundles are today; the fix is a cached prebuilt index, not a faster build.
- The graph page's search box grows a full-text index. One MiniSearch index —
  lazy-loaded from the CDN on first search, pinned to the `7.2.0` the Ruby
  MiniSearch port tracks so a Ruby-built index and the browser's rank
  identically — now backs the graph, catalog and files views: ranked, multi-term
  (`AND`), prefix (as-you-type) and typo-tolerant, over title, id, type, tags and
  **description** — plus each concept's **body** wherever the page already holds
  it (`okf render` bakes every body in, so a static file searches bodies offline;
  the live server keeps bodies lazy, so its index stays metadata-only until a
  backend body index arrives). The graph could not be searched by a leaf's
  description before; now it can. The Files view's **Indexes** tab gets its own
  full-text index too, over each `index.md`/`log.md`'s body — not just its
  filename. Until an index loads — or if the CDN is unreachable — each view falls
  back to its own substring filter, so the box is never dead.
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
- `Esc` clears the graph selection. A dense graph leaves almost no empty canvas
  to click for deselecting; `Esc` now drops the highlight (and lets the URL hash
  forget the node) the same way tapping empty canvas does.
- A title-less concept now wears one name in every view. `catalog` and the §6
  index listing fell back a concept with no `title` to its full id — `area/thing`
  — while the graph node fell back blank-aware to the basename — `thing` — so the
  same concept answered to two labels across two views of one bundle, and a
  `title: ""` slipped past the nil-only `||` to catalog as an empty string. Both
  now fall back the graph's way (`File.basename`, blank-aware), so the label is
  the same wherever the concept appears.
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

## [1.8.0] - 2026-07-17

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
- The inspector's type and tags are filter handles: clicking one focuses the
  graph on that facet — the same jump the stats bars make — and clicking it again
  clears it. The chip lights while its facet is the only filter in play, which is
  exactly when a second click is an undo, so what you see and what the next click
  does are the same question. With another filter set it re-focuses instead,
  rather than throwing away more than the click put there.
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
- The graph page answers `?` with a sheet of every keyboard shortcut, reachable
  from a rail button too — a shortcut list you can only open with a shortcut helps
  whoever needs it least. `/` focuses the current view's search where it has one,
  skipping the view that only reads; the sheet is written against the key handler
  it documents, since a shortcut list that has drifted is worse than none.
- Fixed: a file the reader could not **open** (permissions) threw its errno out
  of the read, so a single locked file took the whole bundle down through every
  verb that reads one — `lint`, `validate`, `catalog`, `server`, `registry set`
  — as a backtrace, under an exit code claiming the bundle was non-conformant.
  §9's best-effort promise covers it now, the same as frontmatter that will not
  parse: the file is skipped, noted on stderr, and reported by `validate` under
  §9.1 naming the file and the errno. One bad file never breaks the rest.
  The stderr note reads `skipped N unusable file(s)` — it counts two kinds now,
  so it names neither and points at `validate`, which names both.

- Fixed: `okf registry del <path>` could delete the wrong bundle. A path that
  matched no registered directory fell through to a normalized *slug* lookup, so
  `del ./notes` — naming a local directory — removed whichever entry happened to
  be slugged `notes`, wherever it pointed, and reported `removed notes` with exit
  0. An argument with a `/` in it now names a location and only a location.
- Fixed: the registry read trusted stored slugs verbatim while both write paths
  normalized, so a hand-typed `"slug": "My Docs"` listed fine but could not be
  named by `@my-docs`, `registry rename`, or `registry default` — the verbs that
  could repair it were the ones that could not see it. The read normalizes now,
  leaving an already-usable slug untouched. This also removes the only way a
  quote could reach a slug, and with it a DOM XSS in the server's bundle
  switcher, whose JS escape covered `& < >` but not quotes; the escape now covers
  quotes too, so the page does not depend on a guarantee three layers away.
- Fixed: `okf lint` bucketed a whitespace-only `type` under its own literal
  heading while `types`/`graph`/`stats` bucketed it as `Untyped`, so two verbs
  reported type inventories for the same bundle that would not reconcile. §9.2
  makes a blank type as non-conformant as a missing one; both sides say so now.
- Fixed: `okf search <dir> --fields slug` passed the field guard and returned one
  empty object per match with exit 0. Only registry mode labels rows with a slug,
  so the two modes now declare the shape each actually emits and a path-named
  search names the fields it does have.
- Fixed: `okf registry set` reported `(0 concepts)` for a bundle whose files it
  could not read; it notes the skipped files like every other reading verb.
  `okf registry rename DOCS handbook` echoed the argv rather than the slug it
  renamed, naming a bundle that never existed. An unwritable `$OKF_HOME` raised
  a bare `Errno::EACCES` at exit 1 instead of a usage error at exit 2.
- Fixed: a long path in the Files view's Indexes tab pushed its `map`/`log` badge
  past the right edge of the list. The badge was already pinned and unshrinkable;
  the filename beside it was the problem — a bare text node, and an anonymous flex
  item's automatic minimum size is the full width of its text, so it refused to
  give way and drove the badge out instead. It truncates now, with the full path on
  hover. Only a wide enough path in a narrow enough pane reached it, which is why
  it never showed on mobile, where the list runs full width.
- Fixed: the bundle switcher scrolled its own first row out of view as it opened.
  It rendered, and scrolled the active row into view, while the dialog was still
  hidden — and a list that is not being displayed measures zero, so the scroll
  landed arbitrarily.
- Fixed: the `3` (Files) shortcut did nothing once the Indexes tab was open, and
  the palette's Index row would have blanked the page. "Index" is not a view —
  there is no `#view-index`, only the Files view showing its Indexes tab — so
  `setView('files')` from that tab early-returned, and `setView('index')` named a
  view that does not exist. The keyboard and the palette each re-implemented what
  the rail button already did right; both now click the rail item, so the one
  correct path is the only one, and the palette's `current` badge reads the same
  active-tab answer the rail's own highlight does.

## [1.7.0] - 2026-07-16

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
- The Claude Code plugin's `/okf:gem` command now weighs the shape of a
  free-form ask: a question about what the bundle knows routes through the
  search playbook and answers from retrieved concepts instead of guessing.
- Skill efficiency audit: every playbook now takes the CLI's lean paths.
  `maintain` hunts affected concepts with `okf search` and pulls edges via
  `graph --json --minimal` instead of the full-body dump, `menu` reads the
  plain-text reports it only scans, and SKILL.md pins the discipline as a
  rule: skeleton first, bodies last.
- Docs: the CLI reference's server section now reflects the DOMPurify
  sanitization that landed in 1.1.0 (it still said bodies render unsanitized),
  and the server page's link-preview image points at the renamed
  `okfgem.com/og-demo-v2.png`.

## [1.4.0] - 2026-07-12

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

- The graph server page now emits link-preview metadata: Open Graph and Twitter
  Card tags with a social image, plus `theme-color` and `color-scheme`, so a
  shared `okf server` URL unfurls as a proper card in chat and social apps.
- Docs: a themed README hero (light and dark), a GitHub social preview image,
  and Website / Live demo / Claude Code plugin links.

## [1.2.0] - 2026-07-12

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

- The graph server now sanitizes every concept body before rendering it. The
  page runs marked's HTML output through [DOMPurify](https://github.com/cure53/DOMPurify)
  (loaded from the same CDN as Cytoscape and marked) on the way to the DOM, so a
  bundle carrying active content in a Markdown body can no longer script the
  viewer. Inlined graph data was already escaped through `json_for_script`; this
  closes the other path.
- `require "okf"` now loads the pure library only. The two argv-facing shells —
  `OKF::CLI` and the `OKF::Skill` installer — load on demand, from `exe/okf` or
  an explicit `require "okf/cli"` / `require "okf/skill"`. `optparse` moves with
  the CLI, so an embedding app (e.g. a Rails store) that only reaches for the
  in-memory model and on-disk handles no longer pulls in the command-line
  machinery. The CLI itself is unchanged.

## [1.0.0] - 2026-07-12

Initial release.

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
