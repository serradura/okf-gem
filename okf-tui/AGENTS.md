# AGENTS.md

Maintainer guide for okf-tui — `okf-tui` on RubyGems. A full-screen terminal UI
over [Open Knowledge Format](https://github.com/serradura/okf-gem) bundles: read
one, switch between many, configure the registry, and search across all of them
at once. This file documents how to change the code without breaking its
contracts.

This gem is a sibling in the okf-gem monorepo, one directory per gem beside the
baseline `okf/` it depends on. [`../AGENTS.md`](../AGENTS.md) is the repo-level
guide and owns everything above a single gem — the layout, the PR shape, the
release-title convention, the Git attribution rule. What is here is okf-tui's
own: its floor, its dependency limits, its rendering and interaction contracts.
Where the two overlap, the root is the general rule and this is the instance.

## Map

```
lib/okf/tui/
  ui.rb          pure   layout primitives: width, clipping, wrapping, boxes
  model.rb       pure   one bundle, and every answer about it (memoized)
  workspace.rb   shell  the bundles a session can see; the only registry writes
  views.rb       pure   the six screens — row builders, no terminal I/O
  app.rb         shell  state, key loop, frame painting
  cli.rb         shell  the only layer that parses argv, prints, and exits
  refs.rb        shell  argv → bundle dirs, through okf's own ref grammar
lib/okf/plugin.rb  the okf extension seam — registers `okf tui`, and the
                   gem's only entry point: there is no exe/
```

`require "okf/tui"` loads the library only. The argv-facing shell (`cli.rb`)
loads on demand: the plugin's `#call` requires it, and so must any test that
drives it.

**One door.** This gem ships **no executable**. `lib/okf/plugin.rb` registers a
`tui` command with okf's command registry, and `okf tui` is how a user gets here
— there is no second name to install, document and keep working, and no second
argument grammar to drift. There was an `exe/okf-tui` that did nothing but call
the same `CLI.run`; it went before the first release, while removing a name still
cost nobody anything, which is the same call okf-mcp made for the same reason.
Adding one back needs an argument stronger than symmetry with other gems.

The consequence to hold on to: **the dispatcher must add nothing but argv and
the streams.** `plugin_test.rb` pins it by driving the same run both through
`OKF::CLI.start` and straight into `OKF::TUI::CLI.run` and comparing the exit
code and the message. That grammar is not written here either:
`refs.rb` subclasses `OKF::CLI::Command` so a `@slug`, a bare `@`, an `@group`
and the refusal of `@all` all mean exactly what they mean to `okf server`,
including the messages and the exit codes. It reaches a *private* helper
(`resolve_ref_expanding`), which is a deliberate trade — one copy of the grammar,
at the cost of a coupling — and `refs_test.rb` pins the seam by name so okf moving
it fails loudly rather than quietly restoring "not a directory". The same call is
what opts the TUI into registry discovery, since okf's `open_registry` is
`Registry.load(cwd: Dir.pwd)`.

okf reads `plugin.rb` whenever a verb misses or `okf help` runs, so it must stay
cheap: it registers a class and nothing else, and the TTY toolkit is required
inside `#call`. A subprocess test asserts that loading the plugin leaves
`TTY::Box` undefined.

**Keep the advertisement and the behaviour in step.** `help_rows` is what `okf
help` prints, and it is a promise: it read `tui [DIR|@slug…]` for a release while
the CLI rejected every `@slug` as "not a directory". `plugin_test.rb` now asserts
the advertised form actually resolves. The plugin tests no longer skip — they used
to, when the registry seam was newer than any okf release, and that skip was
deleted on its own instruction once the floor could name the okf that ships
`OKF::CLI.register` (1.10.0).

## Hard constraints

1. **It invents no analysis.** okf owns the format, the model, and every
   question this renders — `catalog`, `graph`, `validate`, `lint`, `directories`,
   `hubs`, `skeleton`, `Bundle::Search`, `Registry`. A question the TUI cannot
   answer by asking okf is a question it has no business answering. Reaching past
   the library to parse markdown, walk a directory, or re-derive a count is the
   one change to refuse outright.

   **It targets OKF v0.2, and reads v0.1 as well as okf does.** okf's own rule,
   and it decides every §5 surface here: v0.2 only added optional keys, so a
   bundle that adopted none must not read as deficient — no empty columns, and no
   row saying "unverified" about a family it never had. Two consequences worth
   stating, because both were arrived at by getting them wrong first. A *derived*
   value is not a declared one: §5.3 gives every unverified concept a tier, and
   claiming it would be the false provenance the trust system exists to prevent,
   so `Bundle::RowFilter.shows_trust?` gates the chip, the facet, its counts and
   its narrowing alike — one predicate, or the facet promises rows it will not
   return. And a version is a thing the bundle *says*: `Bundle#okf_version`, never
   a literal. The health view told every reader "legal OKF v0.1" for a release,
   about migrated bundles included.

   **The corollary that keeps biting: when okf renames something, this breaks
   silently.** `area` became `top_dir` in 1.12.0 and every bundle then reported
   one directory, in two places, for a release — no exception, no empty screen,
   just a wrong number that looked like a right one. It happened again with v0.2:
   the catalog's `timestamp` column was removed for `generated_at`, and browse's
   guard was `unless item[:timestamp].to_s.empty?` — so a missing key read as a
   concept with no date and the "updated" row silently stopped rendering, with a
   green suite either side of it. So a derived okf field read here
   wants a test that would notice, and the strongest form is an *agreement*
   test: ask okf the same question and compare. `dirs_test.rb` checks the dir
   facet against `okf dirs --json`'s subtree column and `structure_test.rb` checks
   the traffic section against `okf graph --traffic` row for row, both in-process.
   That catches a drift a formula copied into a comment never would.

2. **Ruby >= 2.4**, the same floor as okf, which takes it from rack: the tool
   should run on whatever Ruby the OS already ships. RuboCop parses at 2.4 and
   catches syntax, but **not APIs**. Do not introduce: `Struct.new(keyword_init:)`,
   `delete_prefix`/`delete_suffix`, `transform_keys`, `Dir.children`,
   `yield_self` (2.5); `to_h { }`, `then`, `rescue`/`ensure` directly inside a
   `do…end` block, endless string slices `str[i..]` (2.6); `filter_map`, `tally`,
   numbered block params (2.7); endless methods, hash shorthand (3.x).

   The truth test — it copies the tree and drops `Gemfile.lock`, because a
   lockfile written by a modern Bundler is one 2.4's own cannot read, and
   mounting the checkout read-only keeps the run from writing one back. **Run it
   from the repo root**, and let it step in here: the Gemfile resolves okf from
   `../okf`, so a container holding only this directory fails at `bundle
   install` before a test runs.

   ```bash
   docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
     "cp -a /src /build && cd /build/okf-tui && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
   ```

3. **No version ceilings for the floor's sake.** `kramdown` and `rouge` have
   lines that need a newer Ruby than 2.4 — but they declare that themselves, so
   resolution already picks the newest each Ruby accepts. Pinning the old lines
   for everyone was tried first and broke on modern Ruby, where kramdown 2.4
   calls a `CGI` method that no longer exists. A ceiling here has to be justified
   by an incompatibility that resolution cannot see.

4. **The runtime dependencies are okf plus the TTY toolkit** — one gem per job
   (`pastel`, `tty-box`, `tty-cursor`, `tty-markdown`, `tty-reader`,
   `tty-screen`) and no more. A seventh TTY gem is a design decision, not a
   convenience; challenge it. Nothing in `lib/` may require a gem the gemspec
   does not name.

5. **Width is measured on the ANSI-stripped text, always.** A composed terminal
   UI breaks the moment a row's display width disagrees with `String#length`,
   which is exactly what colour causes. `Ui::Line` builds a row segment by
   segment, tracking columns spent, and clips a segment *before* colouring it;
   panes are squared off to an exact rectangle before being joined, in both
   directions — a short row smears the pane beside it, a long one wraps and
   shoves the frame down. New rendering goes through `Ui`, never around it.

6. **tty-markdown is never asked to wrap.** Its wrapper (the `strings` gem)
   miscounts ANSI escapes and raises `IndexError` from `String#insert` on
   coloured input. `PARSE_WIDTH` is a width it can never reach, and `Ui.reflow`
   does the wrapping instead. Related: the colour mode is passed to it
   explicitly rather than sniffed from the terminal, which is what lets a test
   turn colour on — see below.

7. **A layout that cannot fit says so rather than clipping.** Health is two panes
   above 112 columns and one pane at a time below it, reached by the same `Tab`
   either way — the key keeps its meaning and the narrow case stops pretending both
   halves fit. Judge a new split by what its *narrowest* column does to the longest
   row it must carry: health's right pane holds a fixed width because every row in
   it is short by construction, and the rows that carry paths are all on the left.

8. **A view returns rows; it never writes to the terminal.** `Views` is pure, so
   a frame is a value a test can assert on. Only `App#paint` prints.

9. **The registry is the user's configuration.** Every write goes through
   `Workspace` and is followed by a reload, so the screen shows what the file
   now says rather than what memory believes. Tests never touch the real
   `~/.okf` — `with_registry` builds one under a temporary `$OKF_HOME`, and
   `with_local_registry` builds a project-local `.okf-registry.json` with an empty
   global one beside it, so a test can prove *which* of the two a run resolved.

   **The line is the registry, not read-versus-write.** The TUI edits the user's
   own configuration freely — `a` registers, `x` removes, `d` sets the default,
   `n` renames, `c`/`+`/`-` build and edit groups, seven of okf's eight `registry`
   verbs — and never writes a bundle: there is no `Bundle::Writer` in `lib/`, and
   authoring belongs to okf's CLI and skill. Judge a proposed write against that
   line, and let okf own the cascades: a group rename reaching every member list
   is `registry.rename`'s job, and the tests assert its effects rather than
   reproducing it.

   **A write that can lose configuration asks first, and names the consequence.**
   `x` always did; `-` shipped without it and deleted a group on one press. The
   question now names the outcome, because "remove a member" and "delete the group"
   are the same keystroke when that member is the last one.

   **Act on a row, not on a set the reader has to compute.** The first `-` removed
   `scope ∩ members` — a set with *no row on screen*. Every misreading of it was
   reasonable, and the one that got reported ("turn the scope off") was destructive.
   The fix that stuck was structural: **the bundles view has three panes**, so two
   rows are selected at once and every editing key names visible rows — `+` is the
   bundle under the bundles cursor joining the group selected below, `-` is the
   member under the members cursor. Only `c` still reads the scope, where naming
   what you have been searching together *is* the gesture.

   `-` did briefly act in the bundles pane too, as the inverse of `+`, and went back:
   the members pane already gives every member a row of its own, and one editing
   gesture with two homes is a wider surface than the flow needs. **A key that lost
   a pane still answers there** — it says which pane it lives in, because a key that
   quietly stopped working is indistinguishable from a broken one.

   **`+` has to change something visible, and what it changes is not the row.** An
   add that leaves the screen alone reads as an add that did not happen, which is how
   this was reported. A bundle row did carry the slug of the group selected below for
   a round, and it went: the column was relative to a cursor in *another pane*, so it
   changed as that cursor moved and read as noise while working in this one. **A
   column that answers a question the reader is not asking is worse than no column.**
   The membership lives in the detail pane instead (`in @docs @everything`), which
   names every group rather than whichever is selected, and the highlighted status
   line names both sides of the write.

   **The groups pane keeps its cursor when it does not have focus**, dimmed, because
   `+` reaches across to that row. The footer tried spelling the slug out instead
   (`+/- join/leave @onm`) and it read as misleading: it claimed a selection that
   nothing on the screen agreed with. A hint that names an off-screen target is worse
   than a vague one — the fix is to make the target visible and let the hint stay
   short.

   **A scope that *is* a group follows that group across an edit to it.** `◉` on a
   group row is set equality, so growing the group without growing the scope emptied
   the mark and left the bundle just added reading as out of scope — one write
   looking like two failures. `App#keeping_group_scoped` re-applies the scope after
   an edit, but only when the group was in force beforehand: re-scoping on every
   edit would replace a selection the reader made by hand, which is the worse
   surprise of the two.

   Related, and more general: **a hint must not borrow the vocabulary of a different
   mechanism** — `◉` means scope here, so labelling a registry write "scoped" is
   close to an instruction to press it. And **reuse a mechanism before adding one**:
   `Tab` already meant "switch pane" in browse and graph, so three panes cost a
   reader nothing new, and `Esc` peels them one at a time before the filter, exactly
   as [esc-peels-one-layer] requires.

   The same rule reaches the status row, which is app-wide: it is either **asking**
   you something or **telling** you something, and it wears yellow for the first and
   cyan for the second. A flash can afford the mark because `#handle` clears it on
   the very next key — it is on screen until the user does anything at all, and
   never longer. It rendered `bright_black` for a release, which made the one line
   reporting what just happened the quietest thing on the screen.

   Each pane owns a cursor (`@cursor`, `@group_cursor`, `@member_cursor`) and the
   groups pane owns a scroll of its own, or paging one list would drag the other.
   `#clamp_cursor` clamps all three and hands focus back when a pane empties, since
   every registry write rebuilds all of them. A key that belongs to another pane
   *says so* rather than going silent — a key that quietly stopped working is
   indistinguishable from a broken one — and `groups_test.rb` asserts that too.

   `okf registry init` is deliberately *not* offered, for a
   different reason than caution: the registry is resolved once at boot, so
   creating one mid-session would either show nothing or swap the whole workspace
   out from under every open view. That is a re-anchoring, not an edit.

   **Which registry a session is on is a question with one answer.** Every other
   okf verb resolves a discovered `.okf-registry.json` before the global
   `$OKF_HOME` one; being the exception is a bug, and was one. `Workspace` takes
   `cwd:` to opt in and reloads through `Registry#reopen` — never
   `Registry.new(path)`, which drops the `relative_base` a local registry's
   portable relative paths are stored against.

## Testing

**Integration first.** `test/integration/` is the critical layer: it drives the
app the way a user does — real keys, real frames, real exit codes. A unit test
proves a method behaves; an integration test proves the *product* behaves.

```
test/
  test_helper.rb              OKF::TUI::TestCase: app_for, render, with_registry,
                              with_local_registry
  fixtures/                   bundles chosen for their standing, not their size
    nested/                   the only one whose directories nest — see below
    provenance/               the only v0.2 one, §5 declared and withheld — below
  integration/
    geometry_test.rb          every row is exactly the terminal width
    browse_test.rb            reading order, rendering, find-in-body
    search_test.rb            deferred search, focus, escalation, the held corpus
    graph_test.rb             facets, and following a concept out
    dirs_test.rb              okf's directory set, and the dir facet
    structure_test.rb         hubs and dir traffic, against okf's own numbers,
                              and health's two panes
    groups_test.rb            registry groups, and scoping a search to one
    refs_test.rb              @slug / @group, and which registry resolves them
    provenance_test.rb        §5 on screen, and what a v0.1 bundle is spared
    signals_test.rb           health colours, the tab flag, the filters
    cli_test.rb               argv, streams, exit codes — CLI.run driven straight
    plugin_test.rb            `okf tui` through okf's registry, and that the
                              dispatcher adds nothing but the streams
    terminal_test.rb          `okf tui` in a real process, through a real pty —
                              the only test that walks process boot + discovery
  unit/                       the two claims no integration test can reach,
                              because they are about the *package*, not the app
    gemspec_test.rb           the declared okf floor tracks the kernel next door
    packaging_test.rb         LICENSE.txt and NOTICE ship, real files, unchanged
```

**`fixtures/nested` exists because every other fixture is one level deep**, and at
one level `dir` and `top_dir` are the same string — so an assertion against them
passes whichever field the code reads, which is exactly how the `area` break
survived. It carries a real tree, an intermediate directory holding no concepts of
its own (`platform/`), and a directory whose only file is a `log.md` (`history/`) —
the two shapes okf 1.13.0 had to fix its own directory set for. Six directories
against three top-level ones: reach for it for anything about `dir`, depth, or
traffic. Keep it conformant and lint-clean, so it stays usable by the health
tests.

**`fixtures/provenance` is the only v0.2 bundle**, and it carries a concept that
declares no §5 family (`untouched.md`) beside four that do — deliberately, so the
suppression rule is a property of the *concept* rather than of the fixture, and one
test can assert both halves against one bundle. Its numbers are chosen to bite:
three of its four `unverified` concepts are claimable, so a trust facet counting
the whole tally would say 4 and narrow to 3. Reach for it for anything about
trust, status, `generated`, `stale_after` or `sources`; reach for a v0.1 fixture to
prove the same surface stays *absent*. Keep it conformant and lint-clean — its one
`info` is the legacy `timestamp:` on `untouched.md`, which is the §13.1 lift under
test.

**Run with colour on, not just off.** Pastel disables colour when stdout is not
a terminal, so a piped test exercises none of the ANSI-aware width, clipping and
wrapping code — the paths most likely to be wrong are exactly the ones a naive
capture cannot see. `geometry_test` runs both modes; `browse_test` forces colour
for the render sweep. That is not thoroughness for its own sake: the
`IndexError` in constraint 6 rendered perfectly in every uncoloured test.

**No suite here runs the okf a user gets.** The `Gemfile` resolves okf from
`../okf`, and in the monorepo that checkout is always there — so the local run,
CI, and the 2.4 container (which copies the whole repo) all exercise *unreleased*
okf. That is the right default: it is what lets a change to the kernel be driven
from the UI without a release, and it is the arrangement okf-mcp has. It also
leaves a checkout-versus-RubyGems gap, with nothing crossing it by default.

Two things stand in that gap, and they cover different halves.
`test/unit/gemspec_test.rb` is the standing one: it fails the moment okf bumps
and the gemspec floor does not follow, so the floor can never quietly come to
admit a kernel this code has outgrown. And a run against the *published* okf is
the one that catches the rest — a released kernel resolves different analysis
output, which is a difference no floor expresses:

```bash
sed '/gem "okf", path:/d' Gemfile > Gemfile.ci-check
BUNDLE_GEMFILE=Gemfile.ci-check bundle install && BUNDLE_GEMFILE=Gemfile.ci-check bundle exec rake
```

The disagreement it catches is silent: okf's lint findings on `fixtures/okf-docs`
have changed between releases before, which is enough to change how many rows the
health view has. **A test whose premise depends on okf's analysis output can pass
here and fail there** — the health scroll tests did exactly that, proving a pane
overflowed by leaning on a lint count. Prove a rendering property from geometry (a
terminal too short to fit) and let the agreement tests be the place okf's numbers
are asserted. Run the block above before pushing anything that reads okf's
analysis, and before a release.

For the 2.4 container in constraint 2, **read its output, not its exit status.**
Piping it through `tail` returns `tail`'s status, which is zero however the run
went.

**Assert what fails for a real reason.** Two traps this suite has already hit,
both worth remembering:

- **A check that crashes tells you less than one that fails.** When an
  assertion's subject can be nil because the thing under test broke, report that
  and skip the dependents rather than raising `NoMethodError` from the middle.
- **Judge a rendered offset against the window the view actually used.** An
  earlier version compared a scroll against a different window size and reported
  a failure that was not one.

**Name things, do not count them.** The browse list holds reserved files as well
as concepts, so `<down><down><down>` is a guess about ordering. `open_concept("overview")`
is a statement about which concept is open.

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

From the repo root, `rake` runs every gem's default task including this one, and
`rake test` every gem's suite — see [`../AGENTS.md`](../AGENTS.md).

CI (`../.github/workflows/main.yml`) runs this gem's default task on every
supported Ruby, 2.4 through the current stable, as its own `okf-tui` job with
`working-directory: okf-tui`. It is one job per gem rather than a gem axis on one
matrix, because the floors diverge. A change is not done until that matrix is
green.

## Releasing

A release is cut **from this directory** — `cd okf-tui` first. Bundler reads the
gemspec in its working directory and derives the tag from it, so the root `rake
release` refuses rather than doing something plausible.

1. Bump `lib/okf/tui/version.rb` and move the `Unreleased` notes in
   `CHANGELOG.md` under the new version.
2. Move the gemspec's `okf` floor if the kernel bumped in the same cycle —
   `test/unit/gemspec_test.rb` fails until it does.
3. `bundle exec rake release` — tags **`okf-tui/vX.Y.Z`**, pushes commits + tag,
   pushes the gem to RubyGems (MFA required).

**The tag prefix is load-bearing, not cosmetic.** The bare `v*` series belongs to
the baseline gem, and the Docker workflow fires on `v*` — so a bare tag pushed
from here would rebuild and republish the *okf* image, `:latest` included, from a
release that ships something else. A glob does not match across `/`, which is the
whole reason `Rakefile` sets `helper.tag_prefix = "okf-tui/"` before `#install`.

`release:guard_clean` is repo-wide: Bundler runs `git diff` with no pathspec, so
an edited file in a sibling gem blocks a release of this one, and all it says is
"There are files that need to be committed first."

Gem packaging detail: `spec.files` comes from `git ls-files` run with `chdir:`
into this directory, minus `test/`, `bin/`, the Gemfile, the Rakefile,
`.rubocop.yml`, `.gitignore` and `AGENTS.md`. Everything at the repo root is
invisible to it, so a new *root* file needs no reject — but a new top-level file
**here** ships unless the gemspec rejects it, so check `gem build` output when
adding one. `.okf/` is not rejected on purpose: the gem ships its own knowledge
bundle. And `LICENSE.txt` and `NOTICE` are real duplicates of the repo root's,
never symlinks — `gem build` packages a symlink as a symlink, RubyGems >= 3.2
refuses to extract one, and older RubyGems (which the 2.4 end of this matrix
runs) installs it dangling, so the gem ships with no licence and exits 0.
`test/unit/packaging_test.rb` pins all three claims.

The PR that carries a version bump is a release PR, and takes the repo-level
shape: the `release` label, the title `Release okf-tui X.Y.Z — <summary>`, and
the body skeleton. [`../AGENTS.md`](../AGENTS.md) owns all three.

## Git

Commits are attributed to the human maintainer only — no AI co-author trailers,
no "generated by" lines, in commits or PRs.

## Working style

- **Think before coding.** State assumptions; if the request is ambiguous, name
  the interpretations instead of picking one silently; push back when a simpler
  approach exists.
- **Simplicity first.** Minimum code that solves the problem — no speculative
  flexibility, no abstractions for single-use code.
- **Surgical changes.** Match the existing style (see `.rubocop.yml` — spaced
  array brackets `[ 1, 2 ]`, double quotes). Don't improve adjacent code; remove
  only orphans your own change created.
- **Verify against a goal.** Turn every task into a check that can fail, and
  prove it can: break the code on purpose and watch the test report it. A green
  suite that cannot go red is not verification. "Works on my Ruby" is not either
  — the floor is.
