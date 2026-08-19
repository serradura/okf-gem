---
type: Component
title: The Suite — Its Layers, and the Two Fixtures That Exist to Bite
description: "What each test file proves, why `nested` and `provenance` were built when twelve fixtures already existed, and the two gaps between this suite and the okf a user actually resolves."
tags: [testing, fixtures, structure]
generated:
  by: human:maintainer
  at: 2026-08-19
---

# Integration first

`test/integration/` is the critical layer: it drives the app the way a user does
— real keys, real frames, real exit codes. A unit test proves a method behaves;
an integration test proves the *product* behaves.

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
  unit/
    gemspec_test.rb           the declared okf floor tracks the kernel next door
    packaging_test.rb         LICENSE.txt and NOTICE ship, real files, unchanged
    bundle_catalog_test.rb    this bundle against the code it describes
```

The three unit tests are there because their claims are about the *package* and
the *documentation*, not the app — no integration test can reach them.

# The two fixtures built to reach a branch nothing else could

**`fixtures/nested` exists because every other fixture is one level deep**, and
at one level `dir` and `top_dir` are the same string — so an assertion against
them passes whichever field the code reads, which is exactly how the `area`
break survived. It carries a real tree, an intermediate directory holding no
concepts of its own (`platform/`), and a directory whose only file is a `log.md`
(`history/`) — the two shapes okf 1.13.0 had to fix its own directory set for.
Six directories against three top-level ones: reach for it for anything about
`dir`, depth, or traffic.

**`fixtures/provenance` is the only v0.2 bundle**, and it carries a concept that
declares no §5 family (`untouched.md`) beside four that do — deliberately, so
the suppression rule is a property of the *concept* rather than of the fixture,
and one test can assert both halves against one bundle. Its numbers are chosen
to bite: three of its four `unverified` concepts are claimable, so a trust facet
counting the whole tally would say 4 and narrow to 3. Reach for it for anything
about trust, status, `generated`, `stale_after` or `sources`; reach for a v0.1
fixture to prove the same surface stays *absent*.

Keep both conformant and lint-clean, so they stay usable by the health tests.
Provenance's one `info` is the legacy `timestamp:` on `untouched.md`, which is
the §13.1 lift under test.

# Run with colour on, not just off

Pastel disables colour when stdout is not a terminal, so a piped test exercises
none of the ANSI-aware width, clipping and wrapping code — the paths most likely
to be wrong are exactly the ones a naive capture cannot see. `geometry_test` runs
both modes; `browse_test` forces colour for the render sweep.

That is not thoroughness for its own sake: the `IndexError` in
[markdown-rendering-trap](/rendering/markdown-rendering-trap.md) rendered
perfectly in every uncoloured test.

# No suite here runs the okf a user gets

The `Gemfile` resolves okf from `../okf`, and in the monorepo that checkout is
always there — so the local run, CI, and the 2.4 container all exercise
*unreleased* okf. That is the right default: it lets a kernel change be driven
from the UI without a release. It also leaves a checkout-versus-RubyGems gap.

Two things stand in that gap, covering different halves.
`test/unit/gemspec_test.rb` is the standing one: it fails the moment okf bumps
and the gemspec floor does not follow. And a run against the *published* okf
catches the rest — a released kernel resolves different analysis output, which
is a difference no floor expresses.

The disagreement it catches is silent: okf's lint findings on
`fixtures/okf-docs` have changed between releases before, which is enough to
change how many rows the health view has. **A test whose premise depends on
okf's analysis output can pass here and fail there** — the health scroll tests
did exactly that, proving a pane overflowed by leaning on a lint count. Prove a
rendering property from geometry (a terminal too short to fit) and let the
agreement tests be the place okf's numbers are asserted.

# Two assertion traps this suite has already hit

* **A check that crashes tells you less than one that fails.** When an
  assertion's subject can be nil because the thing under test broke, report that
  and skip the dependents rather than raising `NoMethodError` from the middle.
* **Judge a rendered offset against the window the view actually used.** An
  earlier version compared a scroll against a different window size and reported
  a failure that was not one.

And one naming rule: **name things, do not count them.** The browse list holds
reserved files as well as concepts, so `<down><down><down>` is a guess about
ordering. `open_concept("overview")` is a statement about which concept is open.

For the 2.4 container, **read its output, not its exit status** — piping it
through `tail` returns `tail`'s status, which is zero however the run went.
