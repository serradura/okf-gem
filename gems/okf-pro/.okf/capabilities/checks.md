---
type: Capability
title: The checks — nine hook names, and the event each one rides
description: What `okf pro hook <name>` accepts, which Claude Code event the scaffold wires it to, what it asks, and what it does when it cannot answer.
---

# The catalogue

`OKF::Pro::CLI::HOOK_NAMES` is the source of truth, and it is strictly narrower
than `NAMES`: the hook door accepts these nine and nothing else, because `run`
dispatches the CI verbs off the same first argv element and a `settings.json`
typo spelling `hook audit` would otherwise install a gate that reads no stdin,
never blocks, and reports "clean." That failure is [gates-only-at-the-hook-door](/contract/gates-only-at-the-hook-door.md).

| name | event | asks |
|---|---|---|
| `guard-verified` | `PreToolUse` on `Edit\|Write\|MultiEdit` | is this edit setting `verified:` on something the owner has not read? |
| `journal-guard` | `PreToolUse` on `Edit\|Write\|MultiEdit` | is this rewriting a past journal day? |
| `shell-guard` | `PreToolUse` on `Bash` | is this command about to write into the bundle behind the other two? |
| `post-edit` | `PostToolUse` on `Edit\|Write\|MultiEdit` | the three below, in one process, sharing one bundle read |
| `check-okf` | (composed into `post-edit`) | does the bundle still validate and lint? |
| `cap-check` | (composed into `post-edit`) | is In flight over the cap? |
| `reconcile-search` | (composed into `post-edit`) | what already says this? (**Law 1**) |
| `stop-gate` | `Stop` | is the day's snapshot line written, and does it agree with the board? (**Law 2**) |
| `session-context` | `SessionStart` | the banner: what is on the board, as the session opens |

`check-okf`, `cap-check` and `reconcile-search` remain addressable on their own
— they are in `CHECKS` and the door accepts them — but the scaffold wires
`post-edit` instead, because the bundle read is the expensive part and three
separate invocations paid for it three times over.

# What they do when they cannot answer

This is the half that matters, and it is the contract rather than a courtesy.

`hook` reads **0 as pass and 2 as block, and every other code — including 1 —
as non-blocking**: the tool call proceeds. So `hook` never returns 1. A gate
that crashes therefore *passes*, from the protocol's side, which is why the
reader scrubs rather than raises, why `CLI.run` refuses anything that still
raises, and why the shell wrapper exists at all — a Ruby checker structurally
cannot refuse on its own absence.

A check that does not apply is not a failure: `Target.for` returns `nil` for an
edit outside any bundle, and the gate passes. A check that could not run says
so, in the same channel it would have used to refuse.

The full table, and the argument, is [exit-codes](/contract/exit-codes.md); the
three ways the seam let an unchecked edit through are
[three-fail-opens](/seam/three-fail-opens.md).
