# AGENTS.md

Maintainer guide for okf-tui — `okf-tui` on RubyGems. A full-screen terminal UI
over [Open Knowledge Format](https://github.com/serradura/okf-gem) bundles: read
one, switch between many, configure the registry, and search across all of them
at once. This file documents how to change the code without breaking its
contracts.

This gem is a sibling in the okf-gem monorepo, one directory per gem under
`gems/`, beside the baseline `gems/okf/` it depends on.
[`../../AGENTS.md`](../../AGENTS.md) is the repo-level guide and owns everything
above a single gem — the layout, the shared testing obligations, the PR shape,
the release-title convention, the Git attribution rule and the working style.
What is here is okf-tui's own: its floor, its dependency limits, its rendering
and interaction contracts. Where the two overlap, the root is the general rule
and this is the instance.

## Read the bundle first

**`.okf/` is this gem's structural documentation and its catalogue, and this
file no longer restates them.** What the code is, where each responsibility
lives, what the six views answer, which kernel calls back them, and how to add
one all live there — once, in the concept that owns them:

| you want | read |
| --- | --- |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, and it names every file |
| whether a capability already exists | [`.okf/capabilities/`](.okf/capabilities/) — the six views and the okf surface, before you build a seventh |
| why a rule is a rule | [`.okf/decisions/`](.okf/decisions/), [`.okf/interaction/`](.okf/interaction/), [`.okf/rendering/`](.okf/rendering/) |
| how to add a view, a key or a panel | [`.okf/testing/adding-a-view.md`](.okf/testing/adding-a-view.md) |

`okf server .okf` from this directory reads it as a graph; `okf search @okf-tui
<term>` searches it from anywhere in the checkout.

The split used to run the other way: this file carried a hand-written Map of
`lib/**` and nothing checked it. `test/unit/bundle_catalog_test.rb` now fails
when a file under `lib/` is named by no concept, when a concept names a file
that is gone, or when the view catalogue and `App::TABS` disagree — so the
structural layer is pinned where it lives, rather than trusted where nobody
looks.

## One door

This gem ships **no executable**. `lib/okf/plugin.rb` registers a `tui` command
with okf's registry, and `okf tui` is how a user gets here. Adding a binary back
needs an argument stronger than symmetry — the general case is the ecosystem
bundle's `@okf-eco decisions/one-door-per-sibling`, and how this seam is put
together is [`.okf/structure/doors.md`](.okf/structure/doors.md).

Three consequences a reviewer checks, all of them pinned:

* **The dispatcher adds nothing but argv and the streams.** `plugin_test.rb`
  drives the same run through `OKF::CLI.start` and straight into
  `OKF::TUI::CLI.run` and compares the exit code and the message.
* **`plugin.rb` stays cheap.** okf reads it whenever a verb misses or `okf help`
  runs, so it registers a class and nothing else; the TTY toolkit is required
  inside `#call`, and a subprocess test asserts that loading the plugin leaves
  `TTY::Box` undefined.
* **The advertisement and the behaviour stay in step.** `help_rows` read
  `tui [DIR|@slug…]` for a whole release while the CLI rejected every `@slug` as
  "not a directory"; the test now asserts the advertised form resolves.

## The contract

Nine rules. Where a concept carries the argument, this is the short form a
reviewer checks against and the link is the rest.

1. **It invents no analysis.** okf owns the format, the model, and every
   question this renders. A question the TUI cannot answer by asking okf is a
   question it has no business answering, and reaching past the library to parse
   markdown, walk a directory or re-derive a count is the one change to refuse
   outright. [`.okf/decisions/invents-no-analysis.md`](.okf/decisions/invents-no-analysis.md).

   **The corollary that keeps biting: when okf renames something, this breaks
   silently** — `area` → `top_dir`, then the catalog's `timestamp` →
   `generated_at`, each shipping a wrong number that looked like a right one
   with a green suite either side. So a derived okf field read here wants a test
   that would notice, and the strongest form is an *agreement* test: ask okf the
   same question and compare. Every drift found so far, and the two agreement
   tests that now stand where they were, are
   [`.okf/decisions/okf-capability-drift.md`](.okf/decisions/okf-capability-drift.md).

   **It targets OKF v0.2, and reads v0.1 as well as okf does** — v0.2 only added
   optional keys, so a bundle that adopted none must not read as deficient. A
   *derived* value is never a declared one, and a version is a thing the bundle
   *says* (`Bundle#okf_version`, never a literal).

2. **Ruby >= 2.4**, the same floor as okf, which takes it from rack. RuboCop
   parses at 2.4 and catches syntax, but **not APIs**: the forbidden list,
   broken out by the version that introduced each name, is `@okf
   design/ruby-floor`, and what taking okf's floor rather than its own costs
   this gem is [`.okf/decisions/ruby-floor.md`](.okf/decisions/ruby-floor.md).
   It binds `test/` too. The container that proves it is under
   [Commands](#commands), and it is **run from the repo root**: the Gemfile
   resolves okf from `../okf`, so a container holding only this directory fails
   at `bundle install` before a test runs.

3. **No version ceilings for the floor's sake.** `kramdown` and `rouge` declare
   their own floors, so resolution already picks the newest each Ruby accepts;
   pinning the old lines for everyone was tried first and broke on modern Ruby.
   A ceiling has to be justified by an incompatibility resolution cannot see.
   [`.okf/decisions/no-version-ceilings.md`](.okf/decisions/no-version-ceilings.md).

4. **The runtime dependencies are okf plus the TTY toolkit** — one gem per job
   (`pastel`, `tty-box`, `tty-cursor`, `tty-markdown`, `tty-reader`,
   `tty-screen`) and no more. A seventh is a design decision, not a convenience;
   challenge it. Nothing in `lib/` may require a gem the gemspec does not name —
   the one accepted exception, and the test that fails loudly if it stops
   arriving, is
   [`.okf/decisions/undeclared-width-dependency.md`](.okf/decisions/undeclared-width-dependency.md).

5. **Width is measured on the ANSI-stripped text, always.** A composed frame
   breaks the moment a row's display width disagrees with `String#length`, which
   is exactly what colour causes. New rendering goes through `Ui`, never around
   it. [`.okf/rendering/ansi-aware-width.md`](.okf/rendering/ansi-aware-width.md).

6. **tty-markdown is never asked to wrap.** Its wrapper miscounts ANSI escapes
   and raises `IndexError` on coloured input, so `PARSE_WIDTH` is a width it can
   never reach and `Ui.reflow` wraps instead. The colour mode is passed
   explicitly rather than sniffed, which is what lets a test turn colour on.
   [`.okf/rendering/markdown-rendering-trap.md`](.okf/rendering/markdown-rendering-trap.md).

7. **A layout that cannot fit says so rather than clipping.** Health is two
   panes above 112 columns and one pane at a time below it, reached by the same
   `Tab` either way — the key keeps its meaning and the narrow case stops
   pretending both halves fit. Judge a new split by what its *narrowest* column
   does to the longest row it must carry: health's right pane holds a fixed
   width because every row in it is short by construction, and the rows that
   carry paths are all on the left.

8. **A view returns rows; it never writes to the terminal.** `Views` is pure, so
   a frame is a value a test can assert on, and only `App#paint` prints. That is
   what makes the suite renderable without a terminal at all —
   [`.okf/rendering/whole-frame-painting.md`](.okf/rendering/whole-frame-painting.md).

9. **The registry is the user's configuration, and that is the line.** The
   boundary the side effects sit on is not read-versus-write, it is the registry
   versus the knowledge: the TUI edits the former and never the latter. A write
   that can lose configuration asks first and names the consequence; an edit acts
   on a row rather than on a set the reader has to compute. All of it, including
   `registry init` sitting on the far side, is
   [`.okf/decisions/registry-write-boundary.md`](.okf/decisions/registry-write-boundary.md),
   and the interaction rules the panes obey are
   [`.okf/interaction/`](.okf/interaction/).

   **Which registry a session is on is a question with one answer.** okf
   resolves a project-local `.okf-registry.json` before the global `$OKF_HOME`
   one; the TUI did not, and being the single verb that disagreed was a silent
   wrong answer rather than an error.
   [`.okf/interaction/which-registry.md`](.okf/interaction/which-registry.md).

## Testing

**Integration first.** `test/integration/` is the critical layer: it drives the
app the way a user does — real keys, real frames, real exit codes. The
test-first obligations are the root guide's and apply unchanged. What each file
proves, the two fixtures built to reach a branch nothing else could, why the
render sweep runs with colour *on*, and the two assertion traps this suite has
already hit are [`.okf/testing/the-suite.md`](.okf/testing/the-suite.md); the
walk a new view, key or panel owes is
[`.okf/testing/adding-a-view.md`](.okf/testing/adding-a-view.md).

One obligation is this gem's alone, because no other gem in the repo reads
okf's *analysis output*:

> **Run the suite against the *published* okf** before pushing anything that
> reads it, and before a release. No suite here does by default — the Gemfile
> resolves the checkout next door — and a released kernel resolves different
> analysis output, which is a difference no floor expresses.

## Commands

```bash
bin/setup                       # install dependencies
bundle exec rake                # test + rubocop — the default task, what CI runs
bundle exec rake test           # just the suite
# there is no exe/ here — `okf tui` is the entry point, and the bundle resolves
# okf from ../okf, so `bundle exec okf` is the checkout's own CLI
bundle exec okf tui                      # the TUI from the checkout, on your registry
bundle exec okf tui path/to/bundle       # those bundles, ad-hoc
bundle exec okf tui @okf @mkt            # a registered bundle, and a group
OKF_HOME=tmp/home bundle exec okf tui    # a scratch global registry
OKF_NO_DISCOVERY=1 bundle exec okf tui   # ignore a project-local .okf-registry.json

# the suite against the *published* okf, which is what a user resolves — see Testing
sed '/gem "okf", path:/d' Gemfile > Gemfile.ci-check
BUNDLE_GEMFILE=Gemfile.ci-check bundle install && BUNDLE_GEMFILE=Gemfile.ci-check bundle exec rake
```

The 2.4 floor, run from the repo root so the checkout of okf comes with it:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/gems/okf-tui && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

CI runs this gem's default task on every supported Ruby as its own `okf-tui`
job. A change is not done until that matrix is green.

## Releasing

A release is cut **from this directory** — `cd gems/okf-tui` first. Bundler
reads the gemspec in its working directory and derives the tag from it, so the
root `rake release` refuses rather than doing something plausible. The PR that
carries a version bump is a release PR and takes the repo-level shape — the
`release` label, the title `Release okf-tui X.Y.Z — <summary>`, the body
skeleton — all three owned by [`../../AGENTS.md`](../../AGENTS.md).

1. Bump `lib/okf/tui/version.rb` and move the `Unreleased` notes in
   `CHANGELOG.md` under the new version.
2. Move the gemspec's `okf` floor if the kernel bumped in the same cycle —
   `test/unit/gemspec_test.rb` fails until it does.
3. `bundle exec rake release` — tags **`okf-tui/vX.Y.Z`**, pushes commits + tag,
   pushes the gem to RubyGems (MFA required).

**The tag prefix is load-bearing, not cosmetic**, which is why `Rakefile` sets
`helper.tag_prefix = "okf-tui/"` before `#install`: a bare tag pushed from here
would rebuild and republish the *okf* image, `:latest` included, from a release
that ships something else. The argument is the ecosystem bundle's `@okf-eco
decisions/release-and-tags`.

`release:guard_clean` is repo-wide: Bundler runs `git diff` with no pathspec, so
an edited file in a sibling gem blocks a release of this one, and all it says is
"There are files that need to be committed first."

Gem packaging detail: `spec.files` comes from `git ls-files` run with `chdir:`
into this directory, minus `test/`, `bin/`, the Gemfile, the Rakefile,
`.rubocop.yml`, `.gitignore`, `AGENTS.md` and `CLAUDE.md`. A new top-level file
**here** ships unless the gemspec rejects it, so check `gem build` output when
adding one. `.okf/` is not rejected on purpose. `LICENSE.txt` and `NOTICE` are
real duplicates of the repo root's, never symlinks — `gem build` packages a
symlink as a symlink, RubyGems >= 3.2 refuses to extract one, and older RubyGems
(which the 2.4 end of this matrix runs) installs it dangling, so the gem ships
with no licence and exits 0. `test/unit/packaging_test.rb` pins all of those
claims.

## Its own bundle

`.okf/` ships inside the gem, and `rake okf` at the repo root validates and
lints it. Maintain it in the same commit as the code it documents. A new file
under `lib/` without a line in the concept that owns its layer is a red suite,
not a stale document — and so is a view added to `App::TABS` without its row in
the catalogue.
