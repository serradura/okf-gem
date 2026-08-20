---
type: Decision
title: Why the wrapper is a separate shell script
description: A Ruby checker structurally cannot refuse on its own absence, so something already running has to — and it must not exec.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The argument

A script whose interpreter is missing exits 127. A script whose syntax the
interpreter rejects exits 1. [Both are non-blocking](/contract/exit-codes.md).

So a checker written in Ruby cannot refuse when it is missing, broken, or
unparseable: by the time anything could report, nothing is running. That is the
whole job of `.claude/hooks/run`, and it is why `settings.json` points there and
never at `okf` directly.

# It does not exec, and that is a change

The prototype's wrapper ended in `exec`, and carried a comment saying a
SyntaxError "no wrapper can catch, because nothing ran". That was true of an
exec'ing wrapper and is false of this one: after `exec`, the wrapper is gone and
the failing process's status is the answer. Staying resident is what lets it
catch [the third fail-open](/seam/three-fail-opens.md).

# Two things it must not do

**It must not capture stdout.** A `PreToolUse` `ask` decision is JSON on stdout
with exit 0, and the SessionStart banner travels the same way. A draft of this
fix used `rc=$( okf pro hook "$check" )` to read the status — command
substitution captures stdout, so `rc` became output-plus-status, the `case` fell
through to its default, and the most load-bearing gate in the system stopped
asking and started denying. The hardening broke the thing it was hardening.

**It must not resolve `okf` twice.** The binary that proved itself is the binary
that runs: `okf_bin="$(command -v okf)"` once, dispatched to absolutely. A
re-resolution after changing the environment is a different program.

# The residue

`"$CLAUDE_PROJECT_DIR"` stays quoted in `settings.json`. Unquoted, a path with a
space word-splits, the shell exits 127, and all four gates are disarmed by a
directory name.
