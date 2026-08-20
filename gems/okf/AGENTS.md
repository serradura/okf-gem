# AGENTS.md

okf — the baseline gem, `okf` on RubyGems. It reads, validates, lints, searches
and serves Open Knowledge Format (OKF) v0.2 bundles, and ships the companion
skill that teaches an agent to write them. The three siblings under `gems/` all
depend on it.

**This file is context, routing and reference.** [`../../AGENTS.md`](../../AGENTS.md)
binds every change in the repo; what is below is okf's own, and every argument
for it is in `.okf/` rather than here.

## Where to read

| you want | read |
| --- | --- |
| the gem at a glance | [`.okf/overview.md`](.okf/overview.md) |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, naming all fifty files |
| whether a verb already answers this | [`.okf/cli.md`](.okf/cli.md), [`.okf/capabilities/`](.okf/capabilities/) |
| what the format's nouns mean here | [`.okf/model/`](.okf/model/) |
| why a rule is a rule | [`.okf/design/`](.okf/design/) |
| how to add a verb, and what the suite is made of | [`.okf/testing/`](.okf/testing/) |

`okf server .okf` reads it as a graph; `okf search @okf <term>` from anywhere in
the checkout, `okf search @all <term>` across every bundle.

## The contract

Nine rules. Each line is the whole of what you must hold; the link is why.

1. **Ruby >= 2.4**, and it binds `test/` too. RuboCop catches syntax at 2.4 but
   **not APIs** — [`.okf/design/ruby-floor.md`](.okf/design/ruby-floor.md) has
   the forbidden list by version and the container that proves it.
2. **Runtime dependencies are exactly `rack`, `webrick`, `minifts`.** No
   ActiveSupport. A fourth is a design decision —
   [`.okf/design/runtime-dependencies.md`](.okf/design/runtime-dependencies.md).
3. **YAML only through `Markdown::Frontmatter`.** Never call
   `YAML.safe_load`/`YAML.load` anywhere else —
   [`.okf/structure/format-layer.md`](.okf/structure/format-layer.md).
4. **`validate` and `lint` stay separate**, and exit codes are 0 ok / 1 failing
   bundle / 2 usage error. A new check goes to one side or the other —
   [`.okf/capabilities/validator.md`](.okf/capabilities/validator.md),
   [`.okf/capabilities/linter.md`](.okf/capabilities/linter.md).
5. **The server page stays self-contained, and both XSS defenses stay.** A new
   render path that skips `DOMPurify.sanitize` reopens the hole —
   [`.okf/design/server-trust-boundary.md`](.okf/design/server-trust-boundary.md).
6. **The skill ships only from `lib/okf/skill/**`.** Edit there and nowhere else,
   then `rake skill:sync`; `plugin/skills/okf` and `skills/okf` are generated —
   [`.okf/capabilities/agent-skill.md`](.okf/capabilities/agent-skill.md).
7. **Tests subclass `OKF::TestCase`**, nothing else —
   [`.okf/testing/the-harness.md`](.okf/testing/the-harness.md).
8. **Integration first**: `test/integration/cli/` is the critical layer, and it
   wins when it competes with a unit test for effort —
   [`.okf/design/integration-first.md`](.okf/design/integration-first.md).
9. **A new top-level file here ships unless the gemspec rejects it, and nothing
   in `spec.files` may be a symlink.** Check `gem build` output —
   [`.okf/design/packaging.md`](.okf/design/packaging.md).

**The graph page is not done until `rake test:browser` is green.** Nothing
enforces it — it does not run in CI, deliberately. Run it and say what it said.
[`.okf/design/browser-tests.md`](.okf/design/browser-tests.md).

## Commands

```bash
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
bundle exec rake test:integration  # the critical layer alone
bundle exec rake test:browser      # the graph page in real Chromium (needs browser:setup)
bundle exec rake browser:ui        # the same suite, interactive
bundle exec rake serve             # the browser fixture bundle, served by hand
bundle exec rake skill:sync        # regenerate the generated skill copies + version stamp
ruby -Ilib exe/okf <cmd> <dir>     # the CLI from the checkout, no install
```

The 2.4 floor, from the repo root because it copies the whole tree:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/gems/okf && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

## Releasing

From this directory — `cd gems/okf` first; the root `rake release` refuses.

1. Bump `lib/okf/version.rb`, run `bundle exec rake skill:sync` (the plugin
   manifest versions with the gem), move `CHANGELOG.md`'s `Unreleased` notes
   under the new version.
2. `bundle exec rake release` — tags `vX.Y.Z`, pushes commits + tag, pushes to
   RubyGems (MFA). `build` aborts on a drifted skill copy, so a forgotten sync
   stops the release rather than shipping.

`release:guard_clean` is repo-wide, so an edited file in a sibling gem blocks
this release; `release:preflight` runs first and names the paths. The bare `v*`
series is this gem's — `@okf-eco decisions/release-and-tags`. The PR shape is
`@okf-eco design/pull-requests`.

## Its own bundle

`.okf/` ships inside the gem, deliberately — an installed okf carries a real
bundle to open with the tool just installed. Maintain it in the same commit as
the code. A file under `lib/` with no concept naming it is a red suite, and so is
a verb in `CLI.builtins` with no row in `cli.md`.

A concept cannot link out of its bundle, so a reference across the line names the
other in prose: `` `@okf-eco format/frontmatter` ``. Which bundle a fact belongs
to is `@okf-eco design/where-knowledge-lives`.
