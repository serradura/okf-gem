# AGENTS.md

Maintainer guide for okf-gem — `okf` on RubyGems. The gem reads, validates,
lints, and serves Open Knowledge Format (OKF) v0.1 bundles: directories of
Markdown + YAML frontmatter that humans and agents both read. The bundled skill
(`lib/okf/skill/`) documents the format itself; this file documents how to
change the code without breaking its contracts.

## Map

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

Outside `lib/`, `plugin/` and `.claude-plugin/` are the Claude Code plugin and
its marketplace manifest (the repo doubles as the marketplace): one thin command
that routes to the skill's playbooks (`lib/okf/skill/playbooks/`) or to the
skill itself, a PostToolUse curation hook (`plugin/hooks/scripts/curate.rb`,
plain Ruby on the stdlib, same 2.4 floor), and a generated copy of the skill.
Neither ships in the gem (gemspec reject).

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
   committed lockfile is written by a modern Bundler that 2.4's own cannot read
   (`You must use Bundler 4 or greater with this lockfile`), and mounting the
   checkout read-only keeps the run from writing one back:

   ```bash
   docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
     "cp -a /src /build && cd /build && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
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
library API's to prove. Low coverage in `cli.rb`, `registry.rb`, or `server/` is
a **hole**: it means a path a user can reach that no user-shaped test walks.
Chase those, and let the residue tell you honestly which code the CLI cannot
reach at all.

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

```bash
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
bundle exec rake test:integration  # the critical layer alone + coverage/integration/
ruby -Ilib exe/okf <cmd> <dir>     # the CLI from the checkout, no install
ruby -Ilib exe/okf server <dir>    # boot the graph server locally
bundle exec rake plugin:sync       # regenerate the plugin's skill copy + version stamp
```

CI (`.github/workflows/main.yml`) runs the default task on every supported Ruby,
2.4 through the current stable. A change is not done until that matrix is green.

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

1. Bump `lib/okf/version.rb`, then `bundle exec rake plugin:sync` — the plugin
   versions with the gem, so `plugin/.claude-plugin/plugin.json` must follow
   every bump. Move the `Unreleased` notes in `CHANGELOG.md` under the new
   version.
2. `bundle exec rake release` — tags `vX.Y.Z`, pushes commits + tag, pushes the
   gem to RubyGems (MFA required). `release` runs `build`, and `build` aborts
   if the plugin manifest lags the gem version (`rake plugin:verify`), so a
   forgotten sync stops the release instead of shipping.

Gem packaging detail: `spec.files` comes from `git ls-files` minus
`test/`, `bin/`, `.github/`, etc. — a new top-level file ships in the gem unless
the gemspec rejects it, so check `gem build` output when adding one.

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
