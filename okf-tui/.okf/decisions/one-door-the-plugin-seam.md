---
type: Decision
title: One door — the plugin seam is the entry point
description: okf-tui ships no executable; `okf tui` is the only way in, and the registration stays cheap enough that a run wanting `okf lint` pays nothing for it.
tags: [okf-coupling, dependencies, cli]
timestamp: 2026-07-19T18:00:00Z
---

# Overview

okf's CLI dispatches through a registry and finds extensions by convention: any
gem with `okf/plugin.rb` on its load path can add a verb. This gem ships one, and
that file is its **only** entry point: there is no `exe/`, and `okf help` lists
`tui` under `installed extensions:`. It is the second registry this gem plugs
into, after
[the search facade](search-facade-coupling.md) — and unlike that one it carries
no unreleased-API risk, because a plugin file an old okf never discovers is
simply inert.

Installing the gem is the whole installation. There is no config file, no
`okf plugin add`, and nothing to edit in okf — which is the point of a convention
over a list. See okf's
[extension points](https://github.com/serradura/okf-gem/blob/main/.okf/design/extension-points.md).

# One front end, because two would drift

There was an `exe/okf-tui`. It did nothing but call the same `CLI.run` the
plugin's `#call` calls, and it went before the first release, while removing a
name still cost nobody anything. okf-mcp had already made the same call for the
same reason, and its gemspec records it in one line: a second binary that only
aliases a verb is one more name to install, document and keep working.

The cost of keeping it was not the file. It was that **two front ends are two
argument grammars, and the drift between them is invisible** — each one passes
its own tests while they disagree, because nothing compares them. That is not
hypothetical here: `--home` had to be dropped precisely because the same tool
answered differently depending on which door you came through (see below). The
door that survives is the one a user is told about in `okf help`.

What the seam buys instead is discoverability. Somebody who installed okf-tui
finds it in okf's own map without having to learn that a second command exists.

The obligation that replaces the two-door test: **the adapter must carry argv
and the streams and add nothing else.** `plugin_test.rb` drives the same run
through `OKF::CLI.start` and straight into `OKF::TUI::CLI.run`, and compares the
exit code and the message — driven in the same
[headless, stream-injected](../testing/headless-frames.md) style every other
surface here is proven in. `terminal_test.rb` covers what neither of those can,
being in-process: it spawns okf's executable on a real pty, so process boot and
plugin *discovery* are on the path too.

# Registration must not build anything

okf reads `okf/plugin.rb` whenever a verb misses or `okf help` runs. That file
therefore cannot be expensive, and this gem's library is: six TTY gems plus
kramdown and rouge. Somebody typing `okf lint` should not pay for a terminal
toolkit they are not going to see.

So the plugin file registers a class and nothing else; `require "okf/tui/cli"`
happens inside `#call`. A subprocess test asserts that loading the plugin leaves
`TTY::Box` undefined — in-process it would assert nothing, since the suite has
long since loaded it.

This is the same shape as okf's own laziness one level up: discovery itself only
runs for an unknown verb or for `help`, so a built-in verb never even reads this
file.

# `input:` is why the base command carries a terminal

Every verb okf ships is a one-shot read that never looks at stdin. This one
cannot work without it — a full-screen UI with no terminal has nothing to drive —
so `Command` carries an `input:` alongside `out:`/`err:`, and the TUI takes it
from there rather than reaching for `$stdin`.

That is not ceremony. Reaching past the injected streams would put the command
outside the stream discipline
[the whole suite depends on](../testing/headless-frames.md), and it would make
"it refuses to run without a terminal" unassertable through `okf tui` — the
refusal only works because the stream okf handed down is the one the TUI checks.

# It could not ship before okf did, and that debt is paid

The seam was once newer than any okf release, so `okf tui` did not work against
the published gem and this suite would have been asserting against a CLI with no
`register` at all — the same shape as
[the search facade](search-facade-coupling.md). It was handled the way that one
taught rather than discovered again: the plugin tests **skipped, named**, on an
okf without the registry, and the floor stayed honest rather than guessing at a
version that did not exist yet — guessing one is how the last dependency fix
[became the next bug](../testing/ci-matrix.md).

Both debts are settled. `OKF::CLI.register` shipped in okf 1.10.0, the floor now
names `okf >= 2.0, < 3`, and the skip is gone — deleted on its own instruction,
because a skip left in place after the reason for it is gone is a suite that
quietly tests nothing.

One piece of that arrangement stays, and it should: `lib/okf/plugin.rb` raises a
named `LoadError` rather than a bare `NameError` if it is ever required against
an okf without the registry. The floor makes that unreachable through
resolution, and unreachable is not the same as impossible — a second okf ahead
of the intended one on the load path is exactly how it would happen.

# What it cost: the `--home` flag

`okf-tui --home DIR` is gone. okf had dropped its own `--home` before 1.8 for a
reason it wrote down — a flag whose whole job is to name a location `$OKF_HOME`
already names has to be remembered on the verbs that offer it and forgotten on
the ones that do not — and this gem kept it anyway.

That was survivable while `okf-tui` was its own binary. It stopped being
survivable the moment `okf tui` existed, because then the same tool had two
grammars depending on which door you came through. The flag went first and the
binary followed, which is the order the lesson actually arrived in: the drift was
visible before its cause was.

The library keyword is untouched: `App` and `Workspace` still take `home:`, which
is how an embedding app and the suite name a registry without mutating a
process-global. That is exactly the split okf itself draws — the env var is the
CLI's only lever, the keyword is the library's.

# Citations

[1] `lib/okf/plugin.rb` — the whole seam, including why the heavy require is in `#call`.
[2] `okf-tui.gemspec` — the comment recording why there is no `spec.executables`.
[3] `test/integration/plugin_test.rb` — the dispatcher adding nothing but the
    streams, and the subprocess check that registering does not load tty-box.
[4] `test/integration/terminal_test.rb` — okf's own executable on a real pty, the
    one test that walks process boot and plugin discovery rather than the
    in-process dispatcher.
[5] Verified 2026-07-19: `okf --help` lists `tui` under `installed extensions:`;
    `okf validate` still runs without triggering discovery at all.
