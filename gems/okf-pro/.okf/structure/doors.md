---
type: Component
title: The doors, and the constants the contract is written in
description: Three entry points — the plugin verb, the hook adapter, the CI verbs — all through one dispatcher, and the exit codes every one of them answers in.
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/pro.rb` | the contract's constants, the two reads, `NO_RECONCILE`, and the require list that loads everything |
| `lib/okf/plugin.rb` | `OKF::CLI::Pro` — the okf extension seam, and the last Ruby-side line of the contract |
| `lib/okf/pro/cli.rb` | `OKF::Pro::CLI` — dispatch, the verb tables, the flag parser, and the identity marker |
| `lib/okf/pro/version.rb` | `OKF::Pro::VERSION` |

# `pro.rb` is the vocabulary, not a namespace

Three constants, and every exit this gem takes is one of them:

* `PASS = 0`, `BLOCK = 2` — the only two codes the hook protocol reads as
  meaning anything.
* `FAIL = 1` — `audit` only. It is *findings*, which is CI's vocabulary and not
  the hook's; the hook door never returns it, because the protocol reads it as
  proceed.

Then three things every layer above uses. `read_text` is the raw read, as
bytes, forced to UTF-8 and scrubbed — it failed open twice before it looked
like this, once on an unset `LANG` making `Encoding.default_external` US-ASCII
and once on a single invalid byte raising out of `match?`. `read_contained` is
the same read through the kernel's `SafeRead.read!`, for the callers that
already hold a root and must refuse a symlink leaving it. `newline_terminated`
guarantees the final newline a splice depends on.

`require "okf/pro"` loads **everything**, deliberately: this gem is not an
embedding library, it is a checker, and every module is on the path of some
gate. It also refuses at the top — a `LoadError` on `okf` prints
`ENFORCEMENT DEGRADED` and exits 2, rather than letting the edit through.

# `plugin.rb` is where the contract runs out of Ruby

It registers `pro` with the kernel's command registry, and holds a
`rescue Exception` that re-raises `SystemExit`, cop disabled, reason beside it.
The failures it catches are `ScriptError`s, which are not `StandardError`s, and
it must sit **outside** the `require "okf/pro"` it guards — inside the CLI it
could not catch the `LoadError` of the require that reaches it.

That is the first of [three fail-opens](/seam/three-fail-opens.md) this seam had.

A `SyntaxError` here is unreachable from Ruby altogether: discovery rescues
`LoadError, StandardError`, a `SyntaxError` is neither, and no gem code runs at
all. Only the scaffold's shell wrapper can catch that, which is why the wrapper
no longer `exec`s.

# `cli.rb` is one dispatcher and four tables

The verb tables are the catalogue, and they are read rather than copied
wherever a second copy would drift:

| table | what it holds |
|---|---|
| `CHECKS` | the eight hook checks, name to lambda |
| `HOOK_NAMES` | `CHECKS.keys` plus `session-context` — the **only** names the hook door accepts |
| `READERS` | the seven question-answering verbs |
| `WRITERS` | the five verbs that change a file |
| `SCAFFOLD` | `setup`, `upgrade`, `skill` — they take a destination, not a bundle |
| `USAGE` | the printed command list, joined to `help_rows` by a test rather than by a second literal |
| `FLAGS` | what each verb accepts, declared; absence means "accepts none" |

`HOOK_NAMES` exists because `run` dispatches the CI verbs off the same first
argv element a check name arrives in. Without the whitelist a `settings.json`
typo spelling `hook audit` installs a gate that reads no stdin, cannot block,
and reports "clean."

`MARKER` — `okf-pro-enforcer v1` on stderr immediately before a check runs — is
the whole of the wrapper's identity proof, and it is emitted *here* rather than
at the door so that its presence means the check was reached, not merely that
the plugin loaded.
