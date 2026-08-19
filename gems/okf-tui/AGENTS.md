# AGENTS.md

okf-tui — a full-screen terminal UI over OKF bundles: read one, switch between
many, configure the registry, search across all of them at once. A sibling in the
okf-gem monorepo, beside the baseline `gems/okf/` it depends on.

**This file is context, routing and reference.** [`../../AGENTS.md`](../../AGENTS.md)
binds every change in the repo; what is below is okf-tui's own, and every
argument for it is in `.okf/` rather than here.

## Where to read

| you want | read |
| --- | --- |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, naming every file |
| whether a view already answers this | [`.okf/capabilities/`](.okf/capabilities/) — six views and the okf surface |
| why a rule is a rule | [`.okf/decisions/`](.okf/decisions/), [`.okf/interaction/`](.okf/interaction/), [`.okf/rendering/`](.okf/rendering/) |
| how to add a view, a key or a panel | [`.okf/testing/adding-a-view.md`](.okf/testing/adding-a-view.md) |
| what each test layer can and cannot catch | [`.okf/testing/`](.okf/testing/) |

`okf server .okf` reads it as a graph; `okf search @okf-tui <term>` from anywhere
in the checkout.

## The contract

Nine rules. Each line is the whole of what you must hold; the link is why.

1. **It invents no analysis.** okf owns the format, the model and every question
   this renders. Reaching past the library to parse markdown, walk a directory or
   re-derive a count is the one change to refuse outright —
   [`.okf/decisions/invents-no-analysis.md`](.okf/decisions/invents-no-analysis.md).
2. **A derived okf field wants a test that would notice when okf renames it.**
   Every drift found so far shipped a wrong number with a green suite either
   side; the strongest form is an agreement test against okf itself —
   [`.okf/decisions/okf-capability-drift.md`](.okf/decisions/okf-capability-drift.md).
3. **Ruby >= 2.4**, okf's floor, binding `test/` too. The forbidden API list is
   `@okf design/ruby-floor`; what taking okf's floor costs this gem is
   [`.okf/decisions/ruby-floor.md`](.okf/decisions/ruby-floor.md).
4. **No version ceilings for the floor's sake** — the gems declare their own, so
   resolution handles it per-Ruby —
   [`.okf/decisions/no-version-ceilings.md`](.okf/decisions/no-version-ceilings.md).
5. **Dependencies are okf plus the TTY toolkit**, one gem per job, and nothing
   in `lib/` may require a gem the gemspec does not name —
   [`.okf/decisions/undeclared-width-dependency.md`](.okf/decisions/undeclared-width-dependency.md).
6. **Width is measured on ANSI-stripped text, always.** New rendering goes
   through `Ui`, never around it —
   [`.okf/rendering/ansi-aware-width.md`](.okf/rendering/ansi-aware-width.md).
7. **tty-markdown is never asked to wrap** — `Ui.reflow` does it instead, and the
   colour mode is passed explicitly rather than sniffed —
   [`.okf/rendering/markdown-rendering-trap.md`](.okf/rendering/markdown-rendering-trap.md).
8. **A layout that cannot fit says so rather than clipping**, and a new split is
   judged by its narrowest column —
   [`.okf/rendering/fit-or-say-so.md`](.okf/rendering/fit-or-say-so.md).
9. **A view returns rows; only `App#paint` prints**, which is what makes a frame
   a value a test can assert on —
   [`.okf/rendering/whole-frame-painting.md`](.okf/rendering/whole-frame-painting.md).

Two boundaries that decide whether a feature belongs here at all:

- **The registry is the user's configuration, and that is the line** — this
  program edits the registry, never the knowledge —
  [`.okf/decisions/registry-write-boundary.md`](.okf/decisions/registry-write-boundary.md).
- **This gem ships no executable**; `okf tui` arrives through the kernel's plugin
  seam — [`.okf/structure/doors.md`](.okf/structure/doors.md),
  `@okf-eco decisions/one-door-per-sibling`.

**Run the suite against the *published* okf** before pushing anything that reads
okf's analysis, and before a release. Nothing here does by default — the Gemfile
resolves the checkout next door — and a released kernel resolves different
analysis output, which is a difference no floor expresses.

## Commands

```bash
bin/setup                       # install dependencies
bundle exec rake                # test + rubocop — the default task, what CI runs
bundle exec rake test           # just the suite
# no exe/ here — `okf tui` is the entry point, and `bundle exec okf` is the checkout's CLI
bundle exec okf tui                      # on your registry
bundle exec okf tui path/to/bundle       # those bundles, ad-hoc
bundle exec okf tui @okf @mkt            # a registered bundle, and a group
OKF_HOME=tmp/home bundle exec okf tui    # a scratch global registry
OKF_NO_DISCOVERY=1 bundle exec okf tui   # ignore a project-local .okf-registry.json

# against the published okf — see the contract
sed '/gem "okf", path:/d' Gemfile > Gemfile.ci-check
BUNDLE_GEMFILE=Gemfile.ci-check bundle install && BUNDLE_GEMFILE=Gemfile.ci-check bundle exec rake
```

The 2.4 floor, from the repo root so okf's checkout comes with it:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/gems/okf-tui && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

## Releasing

From this directory — `cd gems/okf-tui` first; the root `rake release` refuses.

1. Bump `lib/okf/tui/version.rb`, move `CHANGELOG.md`'s `Unreleased` notes.
2. Move the gemspec's `okf` floor if the kernel bumped — `test/unit/gemspec_test.rb`
   fails until it does.
3. `bundle exec rake release` — tags **`okf-tui/vX.Y.Z`**.

**The tag prefix is load-bearing**: a bare tag from here would republish the
*okf* Docker image, `:latest` included, from a release that ships something else.
`Rakefile` sets `helper.tag_prefix` before `#install` — `@okf-eco
decisions/release-and-tags`. The PR shape is `@okf-eco design/pull-requests`.

A new top-level file here ships unless the gemspec rejects it; `.okf/` is not
rejected on purpose, and `LICENSE.txt`/`NOTICE` are real duplicates rather than
symlinks. `test/unit/packaging_test.rb` pins all of it.

## Its own bundle

`.okf/` ships inside the gem and `rake okf` at the repo root keeps it clean.
Maintain it in the same commit as the code. A file under `lib/` with no concept
naming it is a red suite, and so is a view in `App::TABS` with no catalogue row.
