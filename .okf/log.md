# Update Log

## 2026-08-20

* **`@slug` is prose, not a link target — said once, where the edge rule
  lives.** Four concepts across the three sibling bundles wrote `[okf](@okf)`,
  and it resolves to nothing: `Links.resolve` gates on `.md`, returns `nil`, and
  the validator never sees the link — no edge, no warning, a 404 on GitHub. The
  near-miss spelling `[cli](@okf/cli.md)` is worse in the other direction: it
  resolves *inside* the linking bundle, so §6.1 tolerates a phantom concept in
  the wrong graph. [Cross-links](/format/cross-links.md) now carries both
  failures and the convention that replaces them — the address in backticks,
  `@okf capabilities/linter` — and [a rule nothing
  runs](/design/nothing-runs-it.md) lists it among the obligations no check
  enforces, because nothing rejects a link the resolver silently drops.

## 2026-08-19

* **Governance**: **an `AGENTS.md` is context, routing and reference — the
  bundles are the harness.** The line that decides what stays: a guide keeps
  what a contributor must obey *unprompted* and routes everything they would
  *look up*. You cannot route to a rule you do not know you are about to break,
  so the test-first rule, the attribution rule and each gem's contract stay as
  one-line imperatives; the argument behind every one of them is a link. Five
  concepts were written for facts that had been sitting in a guide only because
  no concept owned them — [the root is not a
  gem](decisions/the-root-is-not-a-gem.md), [how a change is
  proven](design/how-a-change-is-proven.md), and okf's test harness, packaging
  and okf-tui's fit-or-say-so rule in their own bundles.

  Across the five guides: **77,828 → 29,206 bytes**. What an agent loads before
  reading any code fell 67–82% depending on where it stands, worst case 59,236 →
  12,879.

* **Governance**: **an `AGENTS.md` routes; it no longer restates.** Every rule
  whose argument a concept already carried was cut to the one or two sentences a
  reviewer checks against, plus the link. The root's guide dropped the baseline
  gem's contract entirely — `gems/okf/` was the only gem without a guide of its
  own, so its floor, its dependency limits, its testing obligations and its
  release steps moved into one, and the four gems are now symmetric. Two
  conventions that belonged to no gem and no concept became concepts here:
  [the READMEs](design/the-readmes.md) and
  [the shape of a pull request](design/pull-requests.md).

  What made the case was not size but a **drift already shipped**: okf-tui's
  guide ended with a `Working style` section copied from the root's, eight of
  whose fourteen lines had silently diverged, while its own opening paragraph
  declared that the root owned that rule. Two answers, one claim of single
  ownership, and nothing on either page saying the other existed. The principle
  is in [where knowledge lives](design/where-knowledge-lives.md).

  Measured over twelve realistic questions, every one got cheaper and none
  needed a boundary merged back; the worst went 59,236 → 32,164 bytes, and what
  an agent loads before reading any code fell 26–65% depending on where it
  stands.

* **Naming**: **`@okf` is the gem; this bundle is `@okf-eco`.** The kernel had
  been registered as `@okf-kernel` only because the root bundle was squatting on
  the obvious name from when it *was* the kernel's. Someone typing `@okf` is
  almost always asking about the gem's code, so the gem takes it. The ecosystem
  is the thing you arrive at rather than the thing you look up, and it can
  afford the longer name.

* **Migration**: **every bundle in the tree is now OKF v0.2, declared and
  clean.** okf-tui's was the last on v0.1 and the only one carrying the retired
  spellings: 30 concepts moved `timestamp:` under `generated: { by, at }`, and 22
  moved a body `# Citations` list into a `sources:` list — a GitHub URL where the
  entry named a real file, a [scope descriptor](format/okf-0-2.md) where it
  recorded a measurement or a repro. The three concepts whose bodies carried
  positional `[1]` markers were rekeyed to `[^1]` footnotes against
  `sources[].id`, which is §5.1's keyed attribution; the sources nothing cites
  simply lost the id, because an uncited id is a join half-made.

  okf-pro's 37 concepts gained the `generated:` they were missing. The dates are
  **read from git** (`log --follow`, so a rename is not mistaken for authorship)
  rather than stamped with today's — 27 date to the gem's release, 10 to the work
  above. Provenance invented is worse than provenance absent, which is why the
  first pass at this was thrown away when every file came back with the same
  date: that was the day the files *moved*.

  All five now report `✓ conformant` and `✓ healthy`.

* **Structure**: **this bundle is the ecosystem's map, not any gem's.** It had
  been okf's all along — its index read "okf-gem capabilities" — which is why a
  reader looking for the shape of the *repository* found the shape of one gem.
  Everything about okf moved to `gems/okf/.okf/`: the model, the seven
  capabilities, the CLI, the registry and seven design constraints. What is left
  is what belongs to no single gem and governs all of them.

  Six buckets, and a concept for every item in each: [the gems](gems/), [the
  plugin](plugin/), [the skills](skills/), [the resources](resources/), the
  [decisions](decisions/) that could have gone otherwise, and the
  [design](design/) that holds them together. Plus [the format](format/), which
  stays because it is the one thing all four gems and any future non-Ruby
  implementation speak — a reader asking what a §5.1 citation is, is not asking
  about a Ruby gem.

  The cost was paid in edges. 208 of them crossed this bundle before the split;
  every reference that now leaves it was rewritten to name the other bundle in
  prose (`@okf capabilities/linter`), because a concept structurally
  cannot link out of its own bundle — `Path.normalize_relative!` refuses every
  `..` segment. None was dropped silently, and the log went with the gem whose
  history it records.

* **Addition**: **every gem's structural documentation is now its own bundle,
  pinned by its own test.** A maintainer guide's hand-written Map of `lib/**` is
  the documentation most likely to be wrong and least likely to be checked: a
  file can arrive, move or leave and the Map keeps reading plausibly. All four
  gems now carry that Map in `.okf/structure/`, one concept per layer naming
  every file, and each gem's `test/unit/bundle_catalog_test.rb` fails on a file
  no concept names or a concept naming a file that is gone.

  Beside it, three of the four gained a `.okf/capabilities/` catalogue of what
  the gem already answers — the fourteen MCP tools, okf-pro's sixteen verbs and
  nine checks, okf-tui's six views — each pinned against the constant it claims
  to mirror. That half is the one that pays for itself daily: it is the list an
  agent reads *before* building the fifteenth tool or the tenth check, which is
  the rediscovery this format exists to stop.

  `okf` is the exception, on purpose. **This** bundle is still okf's own, so its
  catalogue already lives here and a second copy would be worse than none — two
  tables that can disagree teach a reader to trust neither. So the split for the
  kernel is by *kind*: what the code **is** went to `gems/okf/.okf/structure/`,
  beside the code where a test can hold it to the tree, and what it **means**
  stayed here beside the format and the layout decisions. The one catalogue that
  did exist — the group table in cli (`@okf cli`) — was code-derived and unchecked,
  and the same test now pins it against `OKF::CLI.builtins`, in place.

  Each gem's `AGENTS.md` keeps the contract, the commands and the obligations a
  reviewer checks, and routes to the bundle for the rest — including this
  repository's own `AGENTS.md`, which is `okf`'s maintainer guide as well.

  Five bundles now, and each gem's ships inside it, so an installed copy carries
  a real bundle — its own — for a reader to open with the tool they just
  installed.
* **Update**: **the root README is the menu, not the manual** — every top-level
  name is a boundary and gets one row, and the eight sections that explained how
  the `okf` gem works moved into
  [gems/okf/README.md](https://github.com/serradura/okf/blob/main/gems/okf/README.md),
  which is where its reader already is. A visitor deciding *whether* to care was
  reading eight sections about one of four gems. Persuasion stays at the root —
  the problem, the comparison table, the two diagrams; instruction leaves. The
  obligation that a new verb ships with its README line is the gem's now: the
  root lists doors, and a new gem is what earns a row.
* **Addition**: **this repository validates and lints its own bundles in CI, and
  publishes the recipe it runs** — validator (`@okf capabilities/validator`),
  linter (`@okf capabilities/linter`). `rake okf` existed for as long as the
  bundles did and nothing ran it. The workflow and the copy-paste template in
  `resources/ci/github/` are the same file but for the `BUNDLES` line, so a break
  in the published recipe is a red check here rather than a report from whoever
  pasted it. Both run the published image through a plain `docker run` against
  the mounted checkout — never `container:`, which runs every step inside an
  image that ships no node and so fails at `actions/checkout`. The half that had
  never been tested now is: the image's non-root `okf` user reads a checkout
  owned by another uid, and a writing verb in the same place dies with EACCES.
* **Update**: **every gem lives under `gems/`** —
  [monorepo layout](decisions/monorepo-layout.md). `gems/okf` builds `okf`,
  `gems/okf-mcp` builds `okf-mcp`: the container names where gems live and never
  which gem this is, so the naming rule and the tree's host-versus-plugin
  asymmetry both survive one segment deeper. The concept it reverses said the
  container buys separation the root does not need *at this size*, and records
  what changed rather than reading as if `gems/` had always been the plan. Eight
  classes of path moved with it, and the root `.rubocop.yml` enumeration of four
  gems collapsed to one `gems/**/*` — the entry that was only ever as true as
  the last person to remember it.
* **Addition**: **the repository commits its own registry** —
  bundles manager (`@okf capabilities/bundles-manager`). `.okf-registry.json` at
  the root makes all three bundles addressable as `@okf`, `@okf-tui` and
  `@okf-pro` from anywhere in the tree, with no global setup: `rake okf` reads
  it instead of a constant, and a bare `okf server` mounts each at `/b/<slug>/`.
  Every stored path is relative, so a checkout copied elsewhere still resolves.
  The surprise it carries is that a project-local registry *replaces* the global
  `$OKF_HOME` one rather than adding to it — which three test helpers had
  assumed away by pinning `$OKF_HOME` alone, and which they now close with
  `OKF_NO_DISCOVERY`.


## 2026-08-17

* **Addition**: **the log's own rule now ships with the skill** — durable
  knowledge and shipped behavior, never the process that produced them, as
  `rule:okf-log-durable-only` in the skill's authoring reference. It had been
  this repository's contract alone, which an agent maintaining anyone else's
  bundle never reads.
* **Addition**: **okf-principles enters the repository as its own skill** —
  index first, keyed identity, permissive reading, no tooling required, kind
  over location: the five structural principles the format implies, written to
  be pointed at any instruction artifact. Its own shape is the argument, and it
  is what the CLI reference split above was an application of.


## 2026-08-15

* **Addition**: **[okf-pro](https://github.com/serradura/okf/tree/main/gems/okf-pro)
  joins the repository as its fourth gem**, cut at 1.0.0 — the
  [enforcement layer](gems/okf-pro.md), and the first surface here
  that writes rather than reads. `okf pro setup` generates an agent's whole
  knowledge repository (a blank-slate bundle, the Claude Code hooks behind a
  fail-closed wrapper, a `pre-commit` hook that audits the *staged* tree, a CI
  workflow, the operating skill), and `okf pro hook` runs one gate against one
  hook event. It reaches the kernel through the same
  [extension points](design/extension-points.md) seam and ships **no
  executable**, which here is load-bearing rather than tidy: the wrapper
  dispatches to one absolute `okf` and refuses unless that binary identifies
  itself as the enforcer, and a second entry point would be a second thing to
  recognise on the one path where being wrong means a gate waves an edit
  through. The durable lesson is the seam's, not the gem's: **a deferred require
  moves a load-time failure to call time, and the caller's rescue was written
  for the code being loaded rather than for the loading** — a `LoadError` out of
  `require "okf/pro"` is a `ScriptError`, outside every rescue in okf's
  dispatch, and it exited 1, which the hook protocol reads as *proceed*. Three
  such holes and one silently skipped lint check are recorded with their
  measurements in that gem's own `.okf/`.
* **Addition**: **[okf-tui](https://github.com/serradura/okf/tree/main/gems/okf-tui) joins the
  repository as its third gem**, cut at 1.0.0 — the full-screen terminal UI over
  one bundle or many: six views, the registry and its groups as editable
  configuration, and search across every bundle in scope through one shared
  corpus. It is the second gem to reach the kernel through the
  [extension points](design/extension-points.md) seam, so installing it teaches
  `okf` a `tui` verb with no edit here — and, like okf-mcp, it ships **no
  executable of its own**: the seam is the entry point rather than a second way
  in, because a binary that only aliases a verb is one more name to install and
  document, and two front ends are two argument grammars that drift while each
  passes its own tests. It is the second, too, to hold the line that a
  shell invents no analysis (`@okf capabilities/read-views`) — every number on
  screen is a pure call on the same core the CLI and the graph server use, with
  agreement tests comparing two of them against `okf dirs --json` and `okf graph
  --traffic` row for row. It floors okf at `>= 2.0, < 3`: the ceiling is earned
  rather than conventional, because an okf *major* is where the renames that
  break a shell **silently** come from (`area` → `top_dir`, then `timestamp` →
  `generated_at` — each read as nil, each a wrong number with a green suite
  either side of it).
* **Update**: [the monorepo layout](decisions/monorepo-layout.md) now states that
  **a sibling keeps no repo-level half**: its CI is a job in the root's
  workflow, its `NOTICE` and `LICENSE.txt` are byte-identical duplicates of the
  root's, and the root lint's exclude list has to grow with it — an obligation
  nothing enforces, and which had already silently failed, since `okf-mcp/` was
  never added and the repo-level lint had been re-checking that whole gem
  against okf's 2.4 target since the day it landed.
* **Correction**: **`GemHelper#tag_prefix=` does not exist on every Bundler the
  matrix runs on.** It arrived in Bundler 2.2, and the Bundler each old Ruby
  ships predates it (1.17.3 on 2.4/2.5, 2.1.4 on 2.7), so a sibling's Rakefile
  raises `NoMethodError` at load there and takes `rake test` down before a test
  runs. CI cannot see it — `ruby/setup-ruby` installs a newer Bundler than the
  Ruby ships — and the 2.4 floor run (`@okf design/ruby-floor`) is what caught it,
  which is the argument for that container in one sentence. The guard refuses to
  release rather than releasing unprefixed: an old Ruby is one to test on, never
  one to release from, and a bare `vX.Y.Z` fires the image build for a different
  gem.
