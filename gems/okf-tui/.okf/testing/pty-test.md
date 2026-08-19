---
type: Runbook
title: The One Test That Opens a Terminal
description: A single pty test boots `okf tui` in a real process and walks every view, and the three timing traps that made it flake on the Ruby floor.
tags: [testing, terminal, scar-tissue]
timestamp: 2026-07-18
---

# Why it exists

Every other test calls `App#handle` directly and never opens a terminal, so none
of them can catch a broken key loop, a raw-mode failure, or a verb that will not
boot. This one spawns a real process through a real pty, sends real keypresses,
walks all six views, quits on `q`, and asserts the exit status — plus that the
registry file is byte-identical afterwards.

**It spawns okf's executable, not one of this gem's, because this gem has none**
— the [plugin seam](/decisions/one-door-the-plugin-seam.md) is the only entry
point. That is not a workaround; it is what makes this test cover more than it
used to. It is now the only place the *whole* path a user walks is exercised:
okf boots, misses `tui` among its built-ins, discovers `okf/plugin.rb` on the
load path, registers the verb, and hands it a real terminal. Every other plugin
test drives the dispatcher in-process, which skips process boot and discovery
both.

The executable is asked of RubyGems (`Gem.bin_path("okf", "okf")`) rather than
guessed from a relative path: okf is a path source inside the monorepo and an
ordinary gem outside it, and this has to keep working either way.

It is deliberately *one* test. A pty is slow and timing-dependent; the cheap
[headless frames](/testing/headless-frames.md) carry the coverage, and this
carries the proof that the thing boots and runs at all.

# The three traps

Each of these was a real failure on the Ruby 2.4 floor, and each looks like a
different bug than it is:

**No `$TERM`.** `tty-cursor` shells out to `tput`. A container or CI runner
without `TERM` set paints *nothing at all* — which reads as a hung app, not a
missing environment variable. The spawn passes `"TERM" => "xterm"`.

**An unsized pty.** `TTY::Screen` asks the pty itself before it reads `LINES`
and `COLUMNS`, and an unsized pty reports nothing, so the app paints an empty
frame. `reader.winsize = [ 40, 120 ]` after spawn, not just the env vars.

# The spawn's environment is the isolation

The child gets `OKF_HOME` named explicitly, alongside `TERM`/`LINES`/`COLUMNS`.
That is not tidiness: since [`--home` was dropped](/decisions/one-door-the-plugin-seam.md)
it is the **only** lever on which registry the binary reads, and this is the one
test that runs a real process against a real registry file. Naming it rather
than trusting inheritance is what keeps the run off the user's own `~/.okf` —
the thing the byte-identical assertion above would otherwise be checking on
*their* file.

**Settling on the first byte.** The app hides the cursor *before* it does any
work, so the first bytes arrive immediately while the real boot — Bundler setup,
gem loads, reading every bundle — happens after them. A settle that starts its
short idle timer on the first byte therefore declares an app "settled" before it
has painted, which is exactly what happened on 2.4. The wait is generous until
the buffer contains a `\n`, and short after: a painted frame always has newlines,
the escape sequences before it do not.

# Send one control key per step

`"\t\r"` in a single write can reach the reader as a *single* keypress. Split
control keys into separate steps — a race the test loses only sometimes is worse
than one it loses always.

# Citations

[1] `test/integration/terminal_test.rb` — `SCRIPT`, `settle`, `reap`.
