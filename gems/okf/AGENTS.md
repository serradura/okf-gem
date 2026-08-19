# AGENTS.md

Maintainer guide for okf — `okf` on RubyGems. The baseline gem: it reads,
validates, lints, searches and serves Open Knowledge Format (OKF) v0.2 bundles —
directories of Markdown + YAML frontmatter that humans and agents both read — and
ships the companion skill that teaches an agent to write them. This file
documents how to change the code without breaking its contracts.

This gem is the baseline of the okf-gem monorepo, one directory per gem under
`gems/`, and the three siblings all depend on it.
[`../../AGENTS.md`](../../AGENTS.md) is the repo-level guide and owns everything
above a single gem — the layout, the distribution surfaces, the PR shape, the
release-title convention, the Git attribution rule. What is here is okf's own:
its floor, its dependency limits, its contracts. Where the two overlap, the root
is the general rule and this is the instance.

## Read the bundle first

**`.okf/` is this gem's knowledge, and this file no longer restates it.** What
the code is, what every verb already answers, why each rule is a rule, and how a
change is proven all live there — once, in the concept that owns them:

| you want | read |
| --- | --- |
| the gem at a glance | [`.okf/overview.md`](.okf/overview.md) |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, naming every one of the fifty files |
| what a verb answers | [`.okf/cli.md`](.okf/cli.md) and [`.okf/capabilities/`](.okf/capabilities/) — before you add a verb that already exists |
| what the format's own nouns mean here | [`.okf/model/`](.okf/model/) |
| why a rule is a rule | [`.okf/design/`](.okf/design/) |
| how a change is proven | [`.okf/testing/`](.okf/testing/) |

`okf server .okf` from this directory reads it as a graph; `okf search @okf
<term>` searches it from anywhere in the checkout, and `okf search @all <term>`
reaches every bundle in the repository at once.

`structure/` is the half a test holds to the tree:
`test/unit/bundle_catalog_test.rb` fails when a file under `lib/` is named by no
concept, when a concept names a file that is gone, or when `cli.md`'s group
table disagrees with `OKF::CLI.builtins`. That table was code-derived and
unchecked for its whole life.

## The contract

Nine rules. Where a concept carries the argument, this is the short form a
reviewer checks against and the link is the rest; two of them have no concept
and are stated here in full.

1. **Ruby >= 2.4** — rack's own floor, so the gem runs on the Ruby an OS already
   ships. RuboCop parses at 2.4 and catches syntax, but **not APIs**: the
   forbidden list, broken out by the version that introduced each name, and the
   container command that actually proves the floor, are
   [`.okf/design/ruby-floor.md`](.okf/design/ruby-floor.md). It binds `test/` too.
2. **Runtime dependencies are exactly `rack`, `webrick` and `minifts`.** No
   ActiveSupport — `OKF.blank?` and `Markdown::Frontmatter.stringify_keys` exist
   precisely so it is not needed. A fourth is a design decision, not a
   convenience; the bar the third one cleared, and the honest note that its case
   has since weakened, are
   [`.okf/design/runtime-dependencies.md`](.okf/design/runtime-dependencies.md).
3. **YAML only through `Markdown::Frontmatter`** — `safe_load`, `Date`/`Time`
   permitted, no aliases. The Psych <3.1 positional-argument shim lives there;
   do not call `YAML.safe_load`/`YAML.load` anywhere else.
   [`.okf/structure/format-layer.md`](.okf/structure/format-layer.md).
4. **`validate` and `lint` stay separate.** The spec forbids the validator from
   rejecting broken cross-links or missing optional fields (warnings only); lint
   owns curation findings and never emits conformance errors. New checks go to
   the right side, and exit codes keep the contract: 0 ok, 1 failing bundle, 2
   usage error. [`.okf/capabilities/validator.md`](.okf/capabilities/validator.md)
   and [`.okf/capabilities/linter.md`](.okf/capabilities/linter.md).
5. **The server page stays self-contained** — one ERB template, inline CSS/JS,
   no bundler and no build step. Two XSS defenses hold the line: inlined data
   goes through `json_for_script`, and every fetched body through
   `DOMPurify.sanitize(marked.parse(...))` before it reaches `innerHTML`. Keep
   both — a new render path that skips the sanitizer reopens the hole. The
   boundary in full, including the realpath containment on every read, is
   [`.okf/design/server-trust-boundary.md`](.okf/design/server-trust-boundary.md).
6. **The skill ships only from `lib/okf/skill/**`** — that tree is the single
   canonical copy, so edit it there and nowhere else. `plugin/skills/okf` and
   `skills/okf` at the repo root are *generated*: run `bundle exec rake
   skill:sync` after touching the skill or bumping the version. Two guards fail
   on drift, and `build` depends on one of them.
   [`.okf/capabilities/agent-skill.md`](.okf/capabilities/agent-skill.md); why
   there are two destinations is the ecosystem bundle's `@okf-eco skills/okf-skill`.
7. **Tests use `OKF::TestCase`** (`test/test_helper.rb`): plain Minitest plus
   `test "..."` / block `setup`/`teardown` sugar. Nothing else is the base
   class, and the suite runs on 2.4, so rule 1 applies to `test/` unchanged.
8. **Integration first — `test/integration/cli/` is the critical layer.** It is
   the only place the gem is exercised the way it is actually used: real argv,
   real streams, real exit codes, real files. When a unit test and an
   integration test compete for effort, integration wins. See
   [Testing](#testing) below for what that obliges, and
   [`.okf/design/integration-first.md`](.okf/design/integration-first.md) for
   how the layer is organised.
9. **`.dockerignore` implies the gemspec's reject list, one way only.** Anything
   `.dockerignore` drops from under this directory must also be rejected by the
   gemspec (or be gitignored): `git ls-files` reads the *index*, so a path
   excluded from the Docker build context is still in `spec.files` and
   `gem build` then fails on a file that is not there. **The converse does not
   hold** and must not be "restored" for symmetry — `bin/`, `Gemfile` and
   `Rakefile` are rejected from the gem and stay in the build context on purpose.
   Paths outside this directory need no pairing at all; the gemspec runs with
   `chdir:` here and never sees them.

   The same section's other rule: **nothing in `spec.files` may be a symlink.**
   `gem build` does not resolve one — it writes a symlink into the package,
   warns, and succeeds. RubyGems >= 3.2 then refuses to extract a link pointing
   outside the gem, and **RubyGems < 3.2 has no guard at all**, so on Ruby 2.7
   (RubyGems 3.1.6, inside the supported range) `gem install` exits 0 and
   installs a *dangling* file. The old half of the matrix is the dangerous one:
   the gem installs cleanly and carries no licence. So `LICENSE.txt` and
   `NOTICE` are real duplicates of the root's, and `test/unit/packaging_test.rb`
   pins that they are not symlinks, are byte-identical to the root's, and are
   actually in `spec.files`.

## Testing

`test/integration/cli/` is the critical layer. How it is organised — one file
per command and subcommand, three folders for the three ways a user names a
bundle, what `across_bundles/` obliges even for the verbs that take one, and why
fixtures are the cheap part — is
[`.okf/design/integration-first.md`](.okf/design/integration-first.md). The
step-by-step walk a new verb owes is
[`.okf/testing/adding-a-verb.md`](.okf/testing/adding-a-verb.md).

Four obligations stay in this file, because a reviewer checks them:

- **Test first, and at this level.** A change starts with a failing integration
  test, not with the fix. Run it and read the failure: it must fail for the
  reason you predicted, not because a fixture is missing or a regex has a typo.
  Then write the code and re-run; the same test passes, **unedited**. A test
  written after the fix certifies only the code it was read off, and editing
  test and code together in one pass is how a bug and its test come to agree
  with each other and stay wrong together. A bug report earns a red test before
  a patch.
- **Pure refactors are the exception, not a licence.** They change no behavior,
  so the existing suite is the test and a green run is the proof. If a change is
  too small to fail visibly first, say so — never skip the step quietly.
- **Assertions must be able to fail for a real reason.** Run the CLI, read what
  it actually prints, then assert *that*. Never assert what you assume the code
  does — that is how a green suite certifies a bug.
- **Do not skimp on fixtures.** When a path is unreachable from the existing
  ones, add the fixture; never bend a test toward what the fixtures happen to
  make easy. A branch no fixture can reach is a branch nobody has ever proven.

### The graph page

`lib/okf/render/graph/template.html.erb` is ~1,300 lines of inline JS and CSS,
and its regressions are the kind a string assertion cannot see.
`test/integration/render/` proves the page is *emitted* correctly;
`test/browser/` — Playwright driving real Chromium, every spec run twice — is
what proves it *works*.

It does not run in CI, deliberately and on the evidence, so the obligation is
unhedged: **a change to the template is not done until `rake test:browser` is
green**, and a bug in the page earns a red spec there before it earns a patch.
Nothing enforces it. Run it and say what it said. The argument, the two modes
and the measurement that ended the CI job are
[`.okf/design/browser-tests.md`](.okf/design/browser-tests.md); the three seams
that couple the file's sections are
[`.okf/structure/the-server.md`](.okf/structure/the-server.md).

## Commands

From this directory — everything about the gem, and what CI actually runs:

```bash
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
bundle exec rake test:integration  # the critical layer alone + coverage/integration/
bundle exec rake test:browser      # the graph page in a real Chromium (needs browser:setup)
bundle exec rake browser:ui        # the same suite, interactive — pick specs and watch
bundle exec rake serve             # the browser fixture bundle, served for poking by hand
ruby -Ilib exe/okf <cmd> <dir>     # the CLI from the checkout, no install
bundle exec rake skill:sync        # regenerate every generated skill copy + version stamp
```

The 2.4 floor is proven in a container, run from the repo root because it copies
the whole tree and steps in here:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/gems/okf && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

CI (`../../.github/workflows/main.yml`) runs the default task on every supported
Ruby, 2.4 through the current stable, as its own job with `working-directory:
gems/okf`. A change is not done until it is green.

## Releasing

A release is cut **from this directory** — `cd gems/okf` first. Bundler reads
the gemspec in its working directory and derives the tag from it, so the root
`rake release` refuses rather than doing something plausible. The PR that
carries a version bump is a release PR and takes the repo-level shape — the
`release` label, the title `Release X.Y.Z — <summary>`, the body skeleton — all
three owned by [`../../AGENTS.md`](../../AGENTS.md).

1. Bump `lib/okf/version.rb`, then `bundle exec rake skill:sync` — the plugin
   versions with the gem, so `plugin/.claude-plugin/plugin.json` must follow
   every bump, and both generated skill copies with it. Move the `Unreleased`
   notes in `CHANGELOG.md` under the new version.
2. `bundle exec rake release` — tags `vX.Y.Z`, pushes commits + tag, pushes the
   gem to RubyGems (MFA required). `release` runs `build`, and `build` aborts if
   a generated skill copy has drifted or the plugin manifest lags the gem
   version (`rake skill:verify`), so a forgotten sync stops the release instead
   of shipping.

**The bare `v*` tag series belongs to this gem** and keeps doing so; a sibling
tags `<gem>/vX.Y.Z`. The asymmetry is deliberate and the argument is the
ecosystem bundle's `@okf-eco decisions/release-and-tags`.

`release:guard_clean` is **repo-wide** — Bundler runs `git diff` with no
pathspec, so a half-finished sibling gem or an edited file two levels up blocks
a release of this one, and all Bundler says is "There are files that need to be
committed first." `release:preflight` runs ahead of it and names the paths,
separating this gem's from the rest; it aborts, because guard_clean was going to
anyway and the only question is which message you get. Verified by running, not
pinned by a test: it is release tooling, and nothing in the suite drives rake
tasks.

Gem packaging detail: `spec.files` comes from `git ls-files` run with `chdir:`
here, minus `test/`, `bin/`, the Gemfile, the Rakefile, `.gitignore`,
`.rubocop.yml`, `AGENTS.md`, `CLAUDE.md` and the gemspec itself. Everything at
the repo root is invisible to it, so a new *root* file needs no reject — but a
new top-level file **here** ships unless the gemspec rejects it, so check
`gem build` output when adding one. Rule 9 above is the other half of this.

## Its own bundle

`.okf/` ships inside the gem — the reject list does not name it, deliberately —
so an installed okf carries a real bundle, its own, for a reader to open with
the very tool they just installed. `test/unit/packaging_test.rb` pins that it
ships; `rake okf` at the repo root keeps it validated and lint-clean.

Maintain it in the same commit as the code it documents. A new file under `lib/`
without a line in the concept that owns its layer is a red suite, not a stale
document — and so is a verb added to `CLI.builtins` without its row in `cli.md`.

Which bundle a fact belongs in — this one or the repository's `@okf-eco` — is
the ecosystem bundle's `@okf-eco design/where-knowledge-lives`. The test is
whether the fact survives deleting this gem; if it does, it is not this bundle's.
A concept cannot link out of its own bundle, so a reference across the line
names the other bundle in prose: `` `@okf-eco format/frontmatter` ``.
