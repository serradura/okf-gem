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
  bundle/validator*.rb    pure   spec §9 conformance (hard errors + soft warnings)
  bundle/linter*.rb       pure   curation-quality report (never rejects)
  concept/file.rb         shell  one-file on-disk handle
  bundle/reader|writer|folder.rb  shell  directory <-> Bundle (writer is atomic, validates before publish)
  render/graph.rb + graph/template.html.erb  shell  the whole UI in one self-contained ERB file — `okf render` bakes it (.static), the server serves the same
  server/app.rb           shell  Rack app: / (page), /node, /node/meta, /catalog, /tags, /types, /index, /log
  server/runner.rb        shell  built-in WEBrick <-> Rack bridge (replaces any rackup need)
  skill.rb + skill/       shell  the companion agent skill + its installer
  cli.rb                  shell  the only layer that parses argv, prints, and exits
```

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
   not a convenience; challenge it. `minifts` (the search engine) cleared that
   bar by being pure Ruby with **no dependencies of its own**, the same 2.4
   floor, and no native extension — it is what defers SQLite + FTS5, and being a
   bit-for-bit port of the browser's MiniSearch is what makes the CLI and the
   page rank identically. A fourth gem needs an argument that strong.
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
   tracks so a Ruby-built index and the browser's rank identically),
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

## Releasing

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
