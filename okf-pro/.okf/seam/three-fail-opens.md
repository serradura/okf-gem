---
type: Finding
title: Three fail-opens in the plugin seam
description: Moving the checker behind okf's plugin seam introduced three paths where a failure exits 1 — which the hook protocol reads as "proceed".
---

# The measurements

`okf/exe/okf` is `exit OKF::CLI.start(ARGV)`, and `CLI#dispatch` calls
`command.new(...).call(argv)` with **no rescue**. Discovery's own rescue wraps
`require path` and catches `LoadError, StandardError`.

1. **A `LoadError` from the deferred `require "okf/pro"` is a `ScriptError`**,
   which is not a `StandardError` and is outside every rescue on the path.
   Measured: process exit **1**, edit proceeds. This is what a half-installed or
   partially-deleted gem looks like.
2. **A non-Integer status** lands in the same place. `exit(true)` is 0 and
   `exit(nil)` is 1; neither is a verdict, and a CLI ported from a standalone
   binary plausibly calls `exit`.
3. **A `SyntaxError` in `lib/okf/plugin.rb`** is a `ScriptError` too, so
   discovery does not catch it either. The whole CLI dies with a parse dump and
   exit 1, and **no gem code runs at all** — so neither Ruby-side guard can
   reach it. Only [the wrapper](/seam/the-wrapper.md) can.

# Where the guard has to live, and where it must not

The rescue is in `OKF::CLI::Pro#call`, **outside** the require it guards. It
cannot be inside `Pro::CLI.run`: that method is reached *through* the require
that fails, so it would be a guard against the one thing it cannot witness.

It is `rescue Exception`, which is the cop's textbook mistake everywhere else in
this repo and the correct call exactly here — the failures are `ScriptError`s,
and catching less than `Exception` is the same as catching nothing.

`SystemExit` is re-raised rather than swallowed. `okf/pro.rb` refuses an
under-floor Ruby with `exit 2`, and a rescue that turned that refusal into an
error report would be the fail-open the whole method exists to close.

# The general shape

A deferred require is a load-time failure moved to call time. When the caller's
error handling was written for the code being loaded rather than for the loading
itself, the move creates a hole exactly the width of the exception hierarchy the
caller does not catch.
