# AGENTS.md

Maintainer guide for okf-gem, a monorepo. `okf/` holds `okf` on RubyGems — the
baseline all-in-one gem that reads, validates, lints, and serves Open Knowledge
Format (OKF) v0.1 bundles: directories of Markdown + YAML frontmatter that humans
and agents both read. The bundled skill (`okf/lib/okf/skill/`) documents the
format itself; this file documents how to change the code without breaking its
contracts.

The ecosystem grows as sibling directories — an MCP shell, a TUI, an FTS5
storage engine — each named for the gem it ships. This file is about the
baseline; a sibling inherits the working style and the Git rules below, but not
the 2.4 floor or the dependency limits, which are `okf`'s own.

## Map

The repository — one directory per gem, plus what is not a gem:

```
okf/            the baseline gem; everything below lives inside it
plugin/         the Claude Code plugin — generated skill copy, command, curation hook
.claude-plugin/ the marketplace manifest (the repo doubles as the marketplace)
.okf/           the project's own knowledge bundle
Dockerfile      builds okf/ — from a root context, because the gemspec needs .git
Rakefile        a delegator: `rake` runs every gem's default task
```

Inside the baseline. **Paths below are relative to `okf/`** unless they begin
with `plugin/`, `.claude-plugin/`, `.okf/` or `.github/`:

```
lib/okf/
  path.rb                 pure   path normalization + root-escape guard
  markdown/               pure   format layer: frontmatter (§4), links (§5), citations (§8)
  concept.rb  bundle.rb   pure   the in-memory model (no disk, no stdio)
  bundle/graph.rb         pure   nodes/edges + type/tag indexes
  bundle/search.rb        pure   facade: owns the row/snippet/sort + the engine registry
  bundle/search/{index,scan}.rb  pure   the engines — raw-text scan (default), minifts BM25+
  bundle/validator*.rb    pure   spec §9 conformance (hard errors + soft warnings)
  bundle/linter*.rb       pure   curation-quality report (never rejects)
  concept/file.rb         shell  one-file on-disk handle
  bundle/reader|writer|folder.rb  shell  directory <-> Bundle (writer is atomic, validates before publish)
  render/graph.rb + graph/template.html.erb  shell  the whole UI in one self-contained ERB file — `okf render` bakes it (.static), the server serves the same
  server/app.rb           shell  Rack app: / (page), /node, /node/meta, /catalog, /tags, /types, /index, /log
  server/hub.rb           shell  N bundles at /b/<slug>/, plus the routes only a set can answer:
                                 GET /search (cross-bundle), GET /b/ (the bundles list),
                                 POST /registry/{default,rename,remove,add} — the only writes in the server
  server/runner.rb        shell  built-in WEBrick <-> Rack bridge (replaces any rackup need)
  skill.rb + skill/       shell  the companion agent skill + its installer
  cli.rb                  shell  the command registry, the dispatcher, and `okf help`
  cli/command.rb          shell  the base every verb inherits: streams, refs, shared flags, printers
  cli/<verb>.rb           shell  one file per verb, each registering itself at load
```

The CLI is the only layer that parses argv, prints, and exits. A verb is a
`CLI::Command` subclass answering four questions about itself (`.id`, `.group`,
`.help_rows`, `.hidden?`) and one about a run (`#call(argv)`, returning the exit
status). Privacy is the boundary: `#call` is the whole public surface, so a
helper cannot become a verb by accident.

`CLI.register` is deliberately the same shape as `Search.register` — append-only,
idempotent by id, duck type checked at registration. **The require block at the
bottom of `cli.rb` IS the order `okf help` lists the verbs in**; a test pins it.

That registry is also the extension point. Any gem with `okf/plugin.rb` on its
load path can register a verb, and `okf` finds it — no edit here, no list of
known addons (a test greps `cli.rb` to keep it that way). Discovery is **lazy**:
a built-in never scans, so only an unknown verb or `okf help` pays the ~11ms.
A plugin that raises is skipped and reported on stderr, never fatal.

**Only gems named `okf-*` are loaded** — a naming convention, the one Jekyll
(`jekyll-*`) and Vagrant (`vagrant-*`) use for the same job, which doubles as a
mild guard since `require` runs whatever it loads. Argue it as a convention if it
is ever revisited: the threat it closes is thin, and overselling it invites the
false confidence that is worse than no rule at all.

One rule underneath it *is* load-bearing: **naming a gem must never load it.**
`plugin_gem_name` reads the spec's `full_gem_path` and requires nothing, because
a refusal that happens after the `require` is not a refusal; a test pins it. A
path belonging to no gem stays trusted (`ruby -I`, a Gemfile `path:`, a checkout
— someone put it there). Threat model in
[.okf/design/extension-points.md](.okf/design/extension-points.md).

The core/shell split is _enforced_: `test/unit/boundary_test.rb` fails if a pure
file names a shell class or touches `File`/`Dir`/`FileUtils`/stdio. Put new I/O
in the shell; put new logic in the core, pure.

Outside the gem, `plugin/` and `.claude-plugin/` are the Claude Code plugin and
its marketplace manifest (the repo doubles as the marketplace): one thin command
that routes to the skill's playbooks (`lib/okf/skill/playbooks/`) or to the
skill itself, a PostToolUse curation hook (`plugin/hooks/scripts/curate.rb`,
plain Ruby on the stdlib, same 2.4 floor), and a generated copy of the skill.
Neither ships in the gem — and neither needs a gemspec reject any more, because
`git ls-files` runs with `chdir:` into `okf/` and never sees them.

They stay at the repo root and `rake plugin:sync` stays in the *gem's* Rakefile
pointing up at `../plugin`. Both of its inputs are the gem's — the skill tree
and the version — and keeping the task there is what lets `task build:
"plugin:verify"` remain a plain dependency, the guard that makes a release with
a stale manifest impossible rather than a CI failure after the fact.

The root `Rakefile` runs plain `rake`, not `bundle exec rake`: there is no root
Gemfile, because the gems here do not share a Ruby floor and one lockfile could
never resolve for all of them. It names each gem's `BUNDLE_GEMFILE` explicitly
when it delegates — bundler exports that variable to everything it runs, so a
nested `bundle exec` otherwise inherits the parent's bundle. `rake okf` is what
replaced `ruby -Ilib exe/okf` for this repo's own bundle, and root `rake
release` refuses: Bundler reads the gemspec in its working directory and derives
the tag from it, so a release is cut from the gem's own directory.

The repo-level Ruby — the root Rakefile and the curation hook — sits outside
every gem, so no gem's `rake rubocop` reaches it. The root `.rubocop.yml`
inherits the gem's and covers exactly those two files.

`require "okf"` loads the library only — the model, the analyzers, and the
on-disk handles. The two argv-facing shells, `cli.rb` (and its `optparse`) and
`skill.rb`, load on demand: `exe/okf` requires them, and so must any test that
drives them. An embedding app never pays for the command-line machinery.
`test/unit/loading_test.rb` guards this in a clean subprocess; keep it green when
you touch what `require "okf"` pulls in.

## Hard constraints

1. **Ruby >= 2.4** (rack's own floor — the point is running on the Ruby an OS
   already ships). RuboCop parses at 2.4 and catches syntax, but **not APIs**.
   Do not introduce: `delete_prefix`/`delete_suffix`, `transform_keys`,
   `Dir.children`, `Dir.glob(base:)`, `Struct.new(keyword_init:)`,
   `yield_self` (2.5); `to_h { }`, `then`, `rescue`/`ensure` directly inside a
   `do…end` block, endless string slices `str[i..]`, `YAML.safe_load` keyword
   args outside the Frontmatter shim (2.6); `filter_map`, `tally`, numbered
   block params (2.7); endless methods, hash shorthand (3.x).
   The truth test — it copies the tree and drops `Gemfile.lock`, because the
   lockfile is written by a modern Bundler that 2.4's own cannot read
   (`You must use Bundler 4 or greater with this lockfile`), and mounting the
   checkout read-only keeps the run from writing one back. Run it from the repo
   root; it steps into the gem, because the floor is `okf`'s property and a
   sibling gem will not share it:

   ```bash
   docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
     "cp -a /src /build && cd /build/okf && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
   ```
2. **Runtime dependencies are exactly `rack`, `webrick` and `minifts`.** No
   ActiveSupport — `OKF.blank?` and `Markdown::Frontmatter.stringify_keys` exist
   precisely so it is not needed. A new runtime dependency is a design decision,
   not a convenience; challenge it. `minifts` (the index engine) cleared that
   bar by being pure Ruby with **no dependencies of its own**, the same 2.4
   floor, and no native extension — it is what defers SQLite + FTS5, and being a
   bit-for-bit port of the browser's MiniSearch is what lets `--engine index`
   rank identically to the page. A fourth gem needs an argument that strong.
   Note it now backs a *non-default* engine: the scan leads because a one-shot
   CLI cannot amortize an index build (3.00 s vs 0.24 s at 1,000 concepts). That
   weakens the dependency's case but does not retire it — `--fuzzy` and page
   parity both still need it — and a cached index would restore it outright.
3. **YAML only through `Markdown::Frontmatter`** — `safe_load`, `Date`/`Time`
   permitted, no aliases. The Psych <3.1 positional-argument shim lives there;
   do not call `YAML.safe_load`/`YAML.load` anywhere else.
4. **`validate` and `lint` stay separate.** §9 forbids the validator from
   rejecting broken cross-links or missing optional fields (warnings only);
   lint owns curation findings and never emits conformance errors. New checks go
   to the right side, and exit codes keep the contract: 0 ok, 1 failing bundle,
   2 usage error.
5. **The server page stays self-contained**: one ERB template, inline CSS/JS,
   only Cytoscape, marked, and DOMPurify from a CDN at boot (Mermaid, Panzoom,
   MiniSearch, and the extra layout engines lazy-load from the same CDN on first
   use — MiniSearch on the first search, pinned to the same `7.2.0` the Ruby port
   tracks so an `--engine index` result and the browser's rank identically),
   bodies pulled on demand with `fetch()`. No htmx, no bundler, no build step. Two XSS defenses hold the
   line: inlined data goes through `json_for_script` (escapes `<` so it cannot
   break out of its `<script>`), and every fetched body is run through
   `DOMPurify.sanitize(marked.parse(...))` before it reaches `innerHTML`. Keep
   both — a new render path that skips the sanitizer reopens the hole.
6. **The skill ships only from `lib/okf/skill/**`** — that tree is the single
canonical copy (`okf skill <dest>`installs from it), so edit it there and
nowhere else. Local installs (e.g.`.agents/`, `.claude/`) are gitignored.
`plugin/skills/okf`is a *generated* copy for the Claude Code plugin, so
never edit it there: run`bundle exec rake plugin:sync`after touching the
skill or bumping the version (the task also stamps`plugin/.claude-plugin/plugin.json`), and `test/plugin/sync_test.rb`fails on any drift (file lists and SHA-256 checksums). Signature guidance
lines carry stable markers —`<!-- check:<lint-check-id> -->`when a
deterministic check enforces the point,`<!-- rule:okf-<slug> -->` for
   pure-judgment craft — as anchors for eval pinning and citation. They render
   invisibly and sync verbatim into the plugin copy, so keep them on the line
   they annotate when you edit it.
7. **Tests use `OKF::TestCase`** (`test/test_helper.rb`): plain Minitest plus
   `test "..."` / block `setup`/`teardown` sugar. The tests run on 2.4 too, so
   the API constraints above apply to `test/` as well.
8. **Integration first — `test/integration/cli/` is the critical layer.** It is
   the only place the gem is exercised the way it is actually used: real argv,
   real streams, real exit codes, real files. A unit test proves a method
   behaves; an integration test proves the *product* behaves, so when the two
   compete for effort, integration wins. See the section below for what that
   obliges you to do.
9. **`.dockerignore` and the gemspec's reject list move together.** Whatever the
   one drops from under `okf/`, the other must reject. `git ls-files` reads the
   *index*, so a path excluded from the Docker build context is still listed in
   `spec.files` and `gem build` then fails on a file that is not there. Paths
   outside the gem need no pairing — the gemspec runs with `chdir:` into `okf/`
   and never sees them.
   The same section's other rule: **nothing in `spec.files` may be a symlink.**
   `gem build` writes one into the package as a symlink and RubyGems refuses to
   extract one pointing outside the gem, so `LICENSE.txt` and `NOTICE` are real
   duplicates of the root's rather than links to them. The build succeeds either
   way; only `gem install` fails, on someone else's machine.
   `test/unit/packaging_test.rb` pins both files.

## Testing: integration first

**Every command and subcommand gets its own file**, named for it —
`cli_catalog_test.rb`, `cli_registry_set_test.rb`. Not one file per topic, and
not one file for a verb family: `registry list`/`set`/`del`/`default`/`rename`
are five files, because each is a surface a user invokes on its own. A new verb
or subcommand ships with its file or it is not done.

**The folders are the three ways a user names a bundle**, and a command is
proven in each one it has:

```
test/integration/cli/
  cli_integration_case.rb   the shared base: okf(), with_registry(), okf_server()
  fixtures/                 bundles used by more than one group
  by_dir/                   `okf lint ./docs`      — named by path
  by_registry/              `okf lint @handbook`   — named through the registry
  across_bundles/           `okf search @a @b`     — several at once
  cli_help_test.rb …        the commands that name no bundle (help, version, skill)
  cli_plugin_test.rb        the extension seam — a plugin on the load path
```

Same command, same flags, three identities — because the identity is where the
CLI decides what to answer about, and a verb that works by path can still be
broken by ref. `across_bundles/` covers **every** bundle-taking verb, not just
the two that merge: for the eleven with no multi-bundle form, the test proves a
second bundle is *rejected* (exit 2). That boundary was a real silent-wrong-answer
bug — `okf lint a b` once linted `a`, ignored `b`, and exited 0 — so it is
guarded, not assumed. Classes are namespaced per folder (`module ByDir`,
`module ByRegistry`, `module AcrossBundles`) so three files can share a name.

**Fixtures follow common closure**: a bundle used by one group lives under that
group; one used by several lives in the shared `fixtures/`. Keep them where the
tests that change with them are.

**Exercise the whole surface, not the happy path** — and do it *in every folder
the command appears in*, not once and cited from the others. For each command:
every flag at least once, every output format it offers (human, `--json`,
`--pretty`, `--fields`/`--except`), every filter, every exit code it can return
(`0`/`1`/`2`), and the combinations that actually interact (a filter plus a
projection, `@all` plus a named ref). The CLI is the agent's whole world; an
untested flag is a promise nobody checked.

**Coverage is measured on integration alone**, because the full suite's number
is flattering — unit tests call classes directly and reach code no user can:

```bash
bundle exec rake test:integration   # integration only + coverage/integration/
```

Read the result as a map, not a score. Low coverage in `bundle/writer.rb` or
`concept/file.rb` is *expected* — no CLI verb writes a bundle, so those are the
library API's to prove. Low coverage in `cli/`, `registry.rb`, or `server/` is
a **hole**: it means a path a user can reach that no user-shaped test walks.
Chase those, and let the residue tell you honestly which code the CLI cannot
reach at all.

**Prove that completeness by reading the uncovered lines, not by judgment.** A
green integration run and a flattering aggregate hide the same thing — a branch
only the unit tests reach — so after a feature, diff
`coverage/integration/.resultset.json` for the *uncovered lines in the files you
changed*: each one in a user-reachable file (`cli/`, `registry.rb`, `server/`) is
a missing integration test, however many you already wrote. Three shapes hide
there by habit, because a unit test walked them first: the *second* output format
(the human listing when only `--json` was asserted, or the reverse), an *error*
branch and the exit code it carries, and *malformed-input* robustness (a
hand-edited registry — a cycle, an unnormalized slug, a missing field). Registry
groups shipped with nine integration tests that read as exhaustive and left six
such branches — a whole human-rendering path among them — proven only by unit
tests until the resultset named them.

**Do not skimp on fixtures.** They are the substrate the whole layer stands on; a
bundle committed there is cheaper than a mock and far more honest, and reviewers
can read it. When a path is unreachable from the existing fixtures — a tagged
root-level concept, a registry entry pointing at a deleted directory — **add the
fixture**. Never bend a test toward what the fixtures happen to make easy, and
never let an untestable path stay untested because building the world for it felt
like work. Fixtures are the cheap part. (`rooted` exists because `tags --by area`'s
`(root)` label was unreachable from all twelve fixtures that preceded it — a
branch no fixture can reach is a branch nobody has ever proven.)

**Test first, and at this level.** A change starts with a failing integration
test, not with the fix. Write it in `test/integration/cli/`, run it, and read the
failure: it must fail for the reason you predicted, not because a fixture is
missing or a regex has a typo — those prove nothing about the bug. Then write the
code and re-run; the same test passes, unedited. A test written *after* the fix
only certifies the code it was read off, and editing test and code together in one
pass is how a bug and its test come to agree with each other and stay wrong
together. A bug report earns a red test before it earns a patch.

Pure refactors are the exception, not a licence: they change no behavior, so the
existing suite is the test and a green run is the proof the contract held. If a
change is too small to fail visibly first, say so — never skip the step quietly.

Assertions must be able to fail for a real reason: run the CLI, read what it
actually prints, then assert *that*. Never assert what you assume the code does
— that is how a green suite certifies a bug.

## Commands

From the repo root — plain `rake`, no bundler, because there is no root Gemfile:

```bash
rake                               # every gem's default task, then the repo-level rubocop
rake test                          # every gem's suite
rake okf                           # validate + lint this repo's own .okf bundle
rake serve                         # serve this repo's own .okf as a graph
```

From `okf/` — everything about the gem, and what CI actually runs:

```bash
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
bundle exec rake test:integration  # the critical layer alone + coverage/integration/
bundle exec rake test:browser      # the graph page in a real Chromium (needs browser:setup)
bundle exec rake browser:ui        # the same suite, interactive — pick specs and watch
bundle exec rake serve             # the browser fixture bundle, served for poking by hand
ruby -Ilib exe/okf <cmd> <dir>     # the CLI from the checkout, no install
ruby -Ilib exe/okf server <dir>    # boot the graph server locally
bundle exec rake plugin:sync       # regenerate the plugin's skill copy + version stamp
```

`bundle exec rake` at the root fails with "Could not locate Gemfile", and that
is the intended answer rather than an oversight — see the Map.

CI (`.github/workflows/main.yml`) runs the gem's default task on every supported
Ruby, 2.4 through the current stable, with `working-directory: okf` on both the
job and `ruby/setup-ruby` (the action needs its own input to find the Gemfile it
caches against). It is one job per gem, not a gem axis on the matrix: the floors
diverge, so a shared matrix would be mostly exclusions. A change is not done
until that matrix is green.

## Testing the graph page

`lib/okf/render/graph/template.html.erb` is ~1,300 lines of inline JS and CSS,
and its regressions are the kind a string assertion cannot see: a view that
returns with a canvas Cytoscape measured at 0×0, a filter that stops composing
with the search box, the ≤768px block folding the wrong element, a handler
that throws where the DOM still looks plausible. `test/integration/render/`
proves the page is *emitted* correctly; it cannot prove the page *works*.

`test/browser/` does — Playwright driving real Chromium, asserting DOM state
and computed CSS at real viewport widths, and failing any test where the page
threw. **Every spec runs twice**, once against `okf server` and once against a
`file://` static `okf render`, because the two modes diverge (fetched
endpoints vs. baked `EMBED`) and a pass in one proves nothing about the other.

It is deliberately outside the default `rake` task: it needs node and a ~120MB
Chromium, neither of which belongs on the 2.4 matrix, and the gem takes on no
dependency from it. **It does not run in CI at all**, and that is the whole of
the arrangement: it is a local obligation.

It used to run as a non-blocking job, on the argument that a red-but-passing
check made a regression visible without gating a merge on someone else's CDN.
That argument lost on the evidence. The job failed **5 of its last 7 runs** while
the Ruby matrix stayed green, almost all of it jsdelivr rather than the page —
and the file this section already carried the verdict: *a red browser job that
nobody reads is worth nothing.* A check that is usually red teaches its readers
to ignore it, and a visitor to the repository reads the ✗ as "the gem is broken"
rather than "a CDN was slow". Both costs are real and the signal was not.

So the obligation is unmoved and now unhedged: **a change to the template is not
done until `rake test:browser` is green**, and a bug in the page earns a red spec
there before it earns a patch — the same rule `test/integration/cli/` already
carries. Nothing enforces it, exactly as nothing enforces the PR shape or the
2.4 Docker run. Run it and say what it said.

Both halves of the template open with a section map, and the JS one also names
the three seams that actually couple the sections (`applyGraphFilter`,
`setView`, the lazy caches). Read it before editing; `grep -n '── '` on the
template prints the same list with live line numbers.

The page's CDN libraries are served from a gitignored `test/browser/vendor/` by
`vendor-cache.js` — a read-through cache keyed on the request URL, so a version
bump is a miss rather than a stale hit. A warm run needs no network;
`OKF_NO_VENDOR_CACHE=1` bypasses it, which is how you check the pins still
resolve. It buys robustness, not speed: measured at one worker it is 28.7s
without and 29.0s with, because the suite is CPU-bound and Chromium already
reused those files across contexts.

`test/browser/README.md` covers the fixture, the console-error watch, the
assertion mistakes the suite's first run shook out, and the cache in full.

## The READMEs

There are two, and they are for different readers.

**The root `README.md` is the project's front door** — the ecosystem, not the
gem. It is what GitHub renders and what a link from anywhere lands on, so it
carries the problem statement, the hero images, the comparison table, and the
argument for why any of this exists. It answers "what is OKF and should I care",
then points at the gem.

**`okf/README.md` is the gem's** — it ships inside the `.gem`, and its reader has
already decided. Install, the shortest path to a working bundle, the command
block, one worked example per surface. No hero images: it is read on
rubygems.org and in a terminal.

Neither is a symlink or a generated copy of the other; they say different things.
What follows applies to both.

**The site owns the manual; a README is a front door.** Every verb is
documented at [okfgem.com/docs](https://okfgem.com/docs/), so a README spends
its space on *value and usage* — what this is for, what it buys you, the shortest
path to a working bundle — and links out for the rest. When a passage starts
enumerating flags, spec clauses, API surface or category lists, it has become
reference material: move it to the site and leave a sentence and a link.

What earns its place: the problem in the opening paragraph, the three pieces, the
two diagrams, the comparison table, the four-step start, what a bundle actually
looks like, and one worked example per surface. What does not: clause-by-clause
§9, the six lint categories enumerated, exhaustive library listings, a Ruby
version matrix, or an essay per flag. The version this replaced carried all of
those; they are all still true and all still one link away.

Four rules that outrank taste, because each has already gone wrong here:

- **Every command shown must run, exactly as written.** Not "looks right" — run
  it against this repo's own `.okf` and check the exit status. A README whose
  commands have drifted spends a new reader's trust on their first minute.
- **Every number is measured now, not copied.** Byte counts, concept counts and
  timings go stale as fixtures grow. Re-measure before printing, and if it cannot
  be measured, do not print it. The `index --json` figure carried over from the
  CHANGELOG as 311 KB → 2.6 KB and measured 313 KB → 2.8 KB the same afternoon —
  close enough to look fine, wrong enough to be a fabricated number.
- **A deprecated spelling never appears.** After any CLI change, grep the README
  for the flag you just retired. `--area` outlived its deprecation there by a
  whole feature branch.
- **A new verb ships with its README line**, the same obligation as its test
  file. A verb absent from the command block does not exist to a reader.

**Benchmarks name the shape of what was measured, never where it lives** — "a
400-concept bundle", not a path. Scratch material under `tmp/` is a working
reference, not part of the published record, and must not be named in the README,
the CHANGELOG, `.okf/`, or the skill.

**Alt text carries the whole content of its image.** The hero and overview PNGs
say everything the diagram says, in prose, because the README is read in
terminals, by screen readers, and by agents that never fetch the image.

**Link depth downward, breadth outward.** Each capability row links to the `.okf/`
concept documenting it — this gem's own knowledge is an OKF bundle, and pointing
at it is the argument that the format works. The manual, the guides and the demo
are absolute links to the site.

The prose is the maintainer's, in the README's established voice. Match it rather
than flattening it into neutral documentation register; the same attribution rule
as commits applies (see [Git](#git)).

## Pull requests

Every PR is a written argument for its own diff, and they share one skeleton.
#12, #7 and #15 are good instances of it at three sizes.

1. **A lead paragraph, no heading** — what changes and why, in a sentence or
   three, carrying the issue it settles (`Closes #6.`, `Follow-up to #7.`). A
   reviewer who reads only this must know whether the PR concerns them. Do not
   open with a `## What` or `## Summary` heading: the first paragraph is already
   the summary, and the heading only pushes it below the fold.
2. **`##` sections named for the area they change or the question they settle** —
   "Where the wrap lives", "The design — one template, two modes", "Graph page".
   Named for their content, not their role: "What", "Overview" and "Details"
   read the same on every PR and tell a reviewer nothing about where to skip to.
   A small PR (#8) needs none at all — a lead and a list is a complete body.
3. **`## Verification` last** — the commands actually run, with their real
   numbers. Three rules that outrank the formatting:
   - **A skipped check is stated as skipped, with why.** #1's "Not run: the Ruby
     2.4 Docker floor…" is the model. A bullet nobody ran is worse than no
     bullet, because it spends the reviewer's trust rather than earning it.
   - **A claim carries the evidence it came from** — "~86% (9.7 KB → 1.4 KB)",
     "worst pairwise gap -1px → +39px", not "much smaller" or "better spaced".
     If it was measured, print the measurement.
   - **What can only prove out after merge gets its own section** ("After
     merge"), never a Verification bullet — publishing a demo, uploading an
     image, running a workflow.

**Argue, don't restate.** The diff is one tab away and reviewers can read it; a
body that inventories changed files earns nothing. Spend the space on what the
diff cannot say: the alternative rejected and why (#12 on why the wrap sits at
the boot seam and not in `App`), the bug class a test pins (#12's wiring pin),
the measurement behind a trade-off, the constraint the change had to hold — the
runtime-dependency rule, the 2.4 floor, the core/shell split.

The prose is the maintainer's, under the same attribution rule as commits (see
[Git](#git)).

## Releasing

**A PR that touches `lib/okf/version.rb` is a release PR.** It is everything
above, plus the `release` label and the two fixed shapes below. PRs #1–#15 were
normalized to all three in one pass, so the merged list reads as one series —
match it. The label is what keeps the series queryable
(`gh pr list --state all --label release`) when a title is mistyped.

### The title

```
Release X.Y.Z — <summary>
```

- **`Release X.Y.Z` verbatim** — the literal word, the bare version, no `v`, no
  branch prefix, and never parenthesized at the end. This holds even when the
  bump is not the point of the work; the release a version shipped in should be
  findable by scanning one column.
- **A spaced em dash** — not a colon, not a hyphen. The summary is a phrase, not
  a subtitle.
- **The summary is the CHANGELOG's headline** — the two or three things the new
  section leads with, comma-joined, lowercase but for identifiers and proper
  nouns, no trailing period, one line (past ~80 characters it is listing too
  much). "opt-in search index, the graph's index layer, @slug addressing", not
  "This release adds an opt-in search index."

### The body

The skeleton above, pinned at three points:

- **The lead opens with the cut** — `Cuts **X.Y.Z**.` — and closes with the
  pointer: `CHANGELOG.md` carries the full notes under `## [X.Y.Z] -
  YYYY-MM-DD`. The PR argues the release, the CHANGELOG itemizes it, so the lead
  says what the version is *for* and never re-lists the entries.
- **Verification names the release checks**: `rake`, the 2.4 Docker floor,
  `plugin:verify` (gem and manifest at the same version), `gem build`, and
  `validate`/`lint` on the repo's own `.okf`.
- **The closing line, verbatim**: `` `rake release` (tag, push, RubyGems with
  MFA) is deliberately not run here. `` — the PR is the gate, the human pushes
  the gem.

#15 is the reference instance of both shapes. Nothing enforces any of it — no CI
check reads PR titles or bodies — so it is a maintainer obligation, and the
point of it is that the tag, the CHANGELOG entry and the PR that carried them
stay findable as one thing. A PR with no version bump takes the base skeleton
only: no label, no fixed title (#12, #8, #7).

### The steps

A release is cut **from the gem's own directory** — `cd okf` first. Bundler reads
the gemspec in its working directory and derives the tag from it, so the root
`rake release` refuses rather than doing something plausible.

1. Bump `lib/okf/version.rb`, then `bundle exec rake plugin:sync` — the plugin
   versions with the gem, so `plugin/.claude-plugin/plugin.json` must follow
   every bump. Move the `Unreleased` notes in `CHANGELOG.md` under the new
   version.
2. `bundle exec rake release` — tags `vX.Y.Z`, pushes commits + tag, pushes the
   gem to RubyGems (MFA required). `release` runs `build`, and `build` aborts
   if the plugin manifest lags the gem version (`rake plugin:verify`), so a
   forgotten sync stops the release instead of shipping.

**The bare `v*` tag series belongs to the baseline gem** and keeps doing so. A
sibling tags `okf-mcp/vX.Y.Z`. The asymmetry is deliberate: the Docker workflow
fires on `v*`, and a glob does not match across `/`, so a sibling's release
cannot trigger a build of an image that ships something else. Prefixing
everything would have been tidier and would have ended a public tag series
mid-history to buy nothing.

Gem packaging detail: `spec.files` comes from `git ls-files` run with `chdir:`
into `okf/`, minus `test/`, `bin/`, the Gemfile and Rakefile. Everything at the
repo root is invisible to it, so a new *root* file needs no reject — but a new
top-level file **inside the gem** ships unless the gemspec rejects it, so check
`gem build` output when adding one. Constraint 9 is the other half of this.

## Git

Commits are attributed to the human maintainer only — no AI co-author trailers,
no "generated by" lines, in commits or PRs.

## Working style

- **Think before coding.** State assumptions; if the request is ambiguous, name
  the interpretations instead of picking one silently; push back when a simpler
  approach exists.
- **Simplicity first.** Minimum code that solves the problem — no speculative
  flexibility, no abstractions for single-use code. If 200 lines could be 50,
  rewrite.
- **Surgical changes.** Match the existing style (see `.rubocop.yml` — e.g.
  spaced array brackets `[ 1, 2 ]`, double quotes). Don't improve adjacent
  code; remove only orphans your own change created.
- **Verify against a goal.** Turn every task into a check that can fail: a new
  test, a failing-then-passing repro, the rake default task, the 2.4 Docker
  run. "Works on my Ruby" is not verification here — the floor is.
