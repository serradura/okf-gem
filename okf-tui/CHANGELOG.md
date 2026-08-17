# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The okf floor moves to `>= 2.1, < 3`** — the kernel this gem develops
  against released 2.1.0, and the floor tracks what the suite proves against
  (the gemspec drill enforces equality as the normal state). Nothing here calls
  a 2.1-only surface; the ceiling is unchanged.

## [1.0.0] - 2026-08-15

First release.

### Added

- **Six views over OKF bundles**: bundles, browse, search, graph, health, help.
  It invents no analysis — okf owns the format, the model, and every question on
  screen.
- **It targets OKF v0.2, and reads v0.1 as well as okf does.** The rule is okf's
  own and it decides every §5 surface below: v0.2 only added optional keys, so a
  bundle that adopted none of them must not read as deficient. A v0.1 bundle
  reads as v0.1 — no empty columns, no rows saying "unverified" about a family it
  never had — and §13.1 does the rest, so a v0.1 `timestamp:` shows as the date
  it records, with no actor invented for it because none was ever recorded. Which spec a bundle is on is asked of the bundle (`Bundle#okf_version`)
  rather than assumed: the health view names v0.1 or v0.2 as declared, and calls a
  bundle that declares neither conformant rather than guessing at a number.
- **§5's provenance, on the concept you are reading.** The browse detail pane says
  when a concept was generated and by whom, how many sources back it, when it
  expires, and its status where that status is not the `stable` an absent one
  already means. The trust tier is the one that needs a rule rather than a
  presence check: §5.3 *derives* `unverified` for every concept that verified
  nothing, so printing it unconditionally would paint a provenance verdict onto
  documents that never made one. `Bundle::RowFilter.shows_trust?` is okf's
  predicate — shared with its server and its graph page — and the graph facet
  gates on the same call, so a tier is claimed in exactly one place or in none.
- **`status` and `trust` are the graph's fourth and fifth facets**, offered only
  where the bundle has something to say — a status needs one *declared* value,
  since a column of `stable` is what an undeclared status already means, and
  trust needs one tier okf is willing to claim. Narrowing goes through
  `Bundle::RowFilter.matches?`, so the two folds that make this non-trivial are
  okf's rather than a copy: an absent status reads `stable` here exactly as it
  does under `--status`, and a tier folds both spellings. The count and the
  narrowing read one predicate, so a facet selects precisely the rows it counted.
- **Browse reads a bundle in spec order** — `index.md`, `log.md`, then each
  directory — and renders concept bodies as markdown. `/` looks through whatever
  has focus: a list filters, a document finds.
- **Follow a markdown link out of the document you are reading**: `f` lists what
  it points at, `1`–`9` or `Enter` goes there, `Esc` puts the body back. The list
  comes from okf's own link extraction — the same one the graph builds edges
  with — so a concept reads as its title and a dead link as not written yet.
  Directory links (`[Decisions](decisions/)`, how every index points at its area)
  follow to that directory's `index.md`.
- **`Backspace` returns to wherever a jump started.** Shared by every jump, so
  opening a search hit and following a concept out of the graph are reversible
  too.
- **Search spans every bundle in scope through one shared index**, so the scores
  compare between them; submitted with `Enter` rather than run per keystroke. The
  corpus is built once and held — measured over five registered bundles, 129
  concepts between them: **392 ms** for the first query, then **12–16 ms** for
  every one after. It is built on first use rather than at load — a session that
  never searches should not pay to index bundles nobody opened — keyed on the
  scope, and dropped on any reload, because a held index outliving the set it was
  built from is a wrong answer rather than a slow one.
- **`e` chooses how a query is asked** — `fuzzy`, `text` or `regexp`. okf's index
  and scan disagree *by design*, so offering only the index would leave every term
  glued to a symbol unfindable with nothing on screen saying so. Measured on okf's
  own bundle: the index finds three of the five concepts that say `minifts` (a
  backtick is not punctuation, so a word in a code span indexes as
  `` `minifts` ``), and returns fourteen results for `OKF_HOME` where the scan
  returns five, because it splits the term and matches the halves. `text` is okf's
  own CLI default and has no tokenizer to get in the way; `regexp` is a capability
  only the scan declares. The mode is named on screen beside the query rather than
  living only in a keystroke, the hits are keyed on it so switching re-asks rather
  than relabelling the previous engine's answer, and an unparseable pattern reports
  itself instead of being rescued into "no matches" — which is indistinguishable
  from a term that is genuinely absent. One held corpus serves all three; the scan
  declares no `prepare`, so it reuses the documents rather than an index.
- **A registry filter that matches nothing offers the search**, exactly as browse
  does: `Enter` takes the term to view 3 and searches every bundle for it. A filter
  over a dozen slugs is a narrow thing to be typing, and a term matching none of
  them is usually a question about what the bundles *say*. Both panes have to be
  empty, so a filter naming a group still accepts on `Enter`.
- **The graph is navigable**: pick a type or tag to narrow it, or a concept to
  open it. A concept whose type is blank or absent is named `Untyped` rather than
  hidden — §9.2 requires a type, which makes those concepts exactly what a curator
  is looking for, and okf's own graph index labels them the same way.
- **`dir` is a third facet in the graph view.** okf 1.11.0 made the full directory
  path a filter on six verbs and 1.12.0 deprecated the first-segment `--area` for
  "losing every level below it". Selecting a directory reaches everything beneath
  it, exactly as `--dir` does, and the counts are the subtree counts `okf dirs`
  prints. Offered only where the bundle actually nests: at one level deep every dir
  facet says what a top-level rollup says, which is what `--area` was deprecated
  for being.
- **Each bundle's standing** (conformance, curation) colours it wherever it is
  named, and flags the health tab.
- **Health is two panes: findings on the left, standing on the right.** One page
  mixing a bounded summary with an unbounded findings list, list on top, drops the
  dir traffic and the stats below the fold — and drops them further the more
  findings a bundle has, which is exactly the bundle whose structure you opened the
  view to read. The summary cannot be pushed away, and the two scroll apart: `Tab`
  names which one the keys move. The right pane carries verdicts and numbers and
  never a path, which is what lets it hold a fixed width; the errors behind its
  counts are listed on the left, where the columns are. Below 112 columns the two
  would each be too narrow for the paths a finding is *about*, so the same `Tab`
  shows one at a time instead.
- **Health says which checks did not run.** §5.5's freshness pair is clock-gated,
  and the pure library runs neither unless handed one — so lint reports
  `expired, stale not run — no clock supplied` rather than letting "lint clean"
  stand for a verdict it did not earn. A check that quietly sat out is the one way
  a health screen is worse than no health screen.
- **The bundle's §5 posture, beside its verdicts.** `trust unverified 31` and
  `status stable 22 · deprecated 1` — okf's own lint numbers, unedited, on the
  pane built for numbers. Shown only where the bundle declared something, on the
  same gate the facets use, and a tier the bundle has none of is dropped rather
  than clipped: this pane holds a fixed width because its rows are short by
  construction, and all three tiers with their counts is not.
- **Hubs and directory traffic, on the health view.** `Bundle#hubs` ranks concepts
  by inbound links and says which directories those links come from — the evidence
  for "is this hub well homed?" A hub drawing its majority from outside its own
  top-level dir is flagged, and where a single foreign dir carries that majority it
  is named, because that is the better home the concept has already found.
  `Bundle#skeleton` adds the same question one grain coarser: each directory's
  internal, outbound and inbound traffic, with the internal share as a
  **cohesion**, sorted so the directories with a case to answer come first. A
  directory with no traffic at all reads `—` rather than a `0%` it did not earn.
  Evidence, not verdicts: okf is explicit that near-zero cohesion under heavy
  inbound can be a shared vocabulary doing its job.
- **The directory arcs, under the cohesion table.** The table says how much of a
  directory's traffic stays home; the arcs say where the rest of it goes, which is
  the other half of `graph --traffic` and the half that names a pair. Narrowed to
  the cut okf *fits to the bundle* — asked for rather than guessed, since okf
  measured ten bundles at a fixed weight and got anywhere from 2 arcs to 136 — and
  the row says how many of how many survived it, because a silently shortened list
  reads as a complete one. Cohesion is still computed over every arc, which is
  okf's rule and is asserted, so narrowing the picture never moves the evidence.
- **Registry configuration in place** — `a` registers a bundle, `x` removes one,
  `d` sets the default, `n` renames. Every write goes through okf's `Registry` and
  is followed by a reload, so the screen shows what the file now says rather than
  what memory believes. `okf registry init` is deliberately not offered: the
  registry is resolved once at boot, so creating one mid-session would swap the
  whole workspace out from under every open view rather than edit the one it is on.
- **Registry groups are on screen, and one key scopes a search to one.** A group
  is a named, recursive set of bundles — which is to say a named search scope, and
  the scope is what this view already manages. Groups list under their own heading
  with the bundles they resolve to; `Enter` makes a search cover exactly those, the
  same set `okf search @group` merges into one ranking. The detail pane shows the
  members as the registry records them *and* the bundles they resolve to, because
  for a nested group those differ. A member naming nothing registered is called out
  rather than dropped, and a hand-edited cycle — which okf refuses to create and
  reports by declining to resolve — says so and refuses to be scoped rather than
  silently covering nothing.
- **Groups can be built and edited here too**, which takes the TUI to seven of
  okf's eight `registry` verbs. `c` names the bundles now in scope as a new group,
  because `◉` already means "these bundles" in this view; `+` adds, `-` removes,
  `n` renames and `x` deletes. okf owns every cascade — a rename reaches every
  member list that named the group, a delete drops it from all of them, and a group
  left with no members is deleted.

  **The bundles view is three panes** — the registry's bundles, its groups, and the
  detail of whichever has focus — with `Tab` cycling and `Esc` stepping back out
  one pane at a time. A heading inside the bundle list scrolls away: thirteen
  registered bundles put the groups below the fold on a short terminal, which is no
  way to show something you are meant to select.

  Two panes also mean two selections at once, and that is what makes the editing
  keys direct. Each acts on a row that is on screen: `+` in the bundles pane adds
  the bundle under that cursor to the group selected below, `-` in the members pane
  removes the member under that cursor, and `n`/`x` in the groups pane rename or
  delete the selected group. Nothing consults the search scope except `c`, where
  naming the bundles you have been searching together is the point. The groups pane
  keeps its cursor while the bundles have focus, dimmed, so the row `+` acts on is
  one the reader can point at — and the footer deliberately does not spell that
  group's slug out, since naming an off-screen target claims a selection nothing on
  screen agrees with.

  The removal key reads a row for that reason above all. A `-` acting on the
  *intersection* of the scope and the member list would act on a set with no row
  on screen, so the key could not be predicted without computing it in your head,
  and its most obvious misreading ("turn the scope off") would take a whole group
  with it. Anything that can lose configuration asks first and names the
  consequence — `x`,
  and `-`, which says when the member being removed is the last one and the group
  goes with it. `+`, `c` and `d` add or reorder, and do not ask.

  A `+` has to change something visible, and what it changes is not the row: the
  bundle detail pane lists every group that names the bundle — `in @docs
  @everything` — and the status line names both sides of the write,
  `@minimal joined @docs — 3 bundles`. An edit to a group that *is* the scope in
  force re-applies that scope, in both directions, so set equality keeps holding
  and the bundle just added does not read as out of scope on its own row. A group
  nobody scoped is left alone, since re-scoping on every edit would replace a
  hand-made selection.
- **The status row is either asking you something or telling you something**, and
  it wears yellow for the first and cyan for the second — one colour each tells the
  two apart before a word is read. A flash can afford the mark because the next
  keystroke clears it along with the message, so it cannot become permanent noise.
- **Quitting is `q q`.** A single `q` ends a session on one stray keystroke; the
  first press arms and says so, and any other key disarms it. `Ctrl-c` still quits
  outright.
- **`okf tui` is the entry point, and the only one — this gem ships no
  executable.** okf dispatches through a command registry and finds extensions by
  convention (any gem with `okf/plugin.rb` on its load path can register a verb),
  so installing this gem is the whole installation: no configuration, and `okf
  help` lists `tui` under `installed extensions:`. There is no second binary: one
  that only aliased the verb would be one more name to install, document and keep
  working, and two front ends are two argument grammars waiting to drift, with
  each one passing its own tests while they disagree. What ships instead is one
  adapter that carries argv and the streams and adds nothing else, which a test
  pins by running the same invocation both ways and comparing the message.
- **Every ref form okf's other multi-bundle verb takes**:
  `@slug`, bare `@` for the registry default, `@group` fanned out to its members, a
  vanished member skipped with a note, and `@all` refused by name as search's
  alone. The grammar is *inherited* rather than copied — `OKF::TUI::Refs`
  subclasses `OKF::CLI::Command` for okf's own resolver — so there is one copy of
  it, and a test pins the seam so that okf moving it fails loudly instead of
  quietly restoring "not a directory".
- **A project-local `.okf-registry.json` resolves ahead of the global one**, the
  same as every other okf verb, discovered by walking up from the working
  directory; `OKF_NO_DISCOVERY=1` opts out and `$OKF_HOME` names the global one.
  Reloads go through `Registry#reopen` so a local registry's relative paths keep
  the anchor they are stored against. The library keyword mirrors okf's own rule:
  `Workspace.new(cwd:)` opts in, and an embedding app that passes no cwd stays
  global-only.

### Requires

- **Ruby >= 2.4**, the same floor as okf.
- **`okf >= 2.0, < 3`** — the kernel release that ships OKF v0.2. A real floor and
  not a formality: eleven okf capabilities are load-bearing here, and the gemspec
  lists which and why. Most of them fail *silently* against an older okf — a
  renamed field reads as nil, a missing method is rescued into "no matches" —
  which is why the floor is stated rather than left to chance, and why the boot
  checks stay: `OKF::TUI.search_capable?` and `.spec_capable?` refuse to start and
  name the okf that answered, because resolution cannot stop a second one sitting
  ahead of the intended one on the load path. The ceiling is earned rather than
  conventional, and by the same evidence: an okf *major* is where the silent drift
  comes from (`area` → `top_dir`, then `timestamp` → `generated_at`), so `< 3`
  turns the next one into a resolution failure a maintainer sees instead of a
  wrong number a reader believes.

[1.0.0]: https://github.com/serradura/okf-gem/releases/tag/okf-tui/v1.0.0
