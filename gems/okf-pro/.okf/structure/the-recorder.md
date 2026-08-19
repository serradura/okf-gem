---
type: Component
title: The recorder — telemetry that refuses nothing and still may not lie
description: "`friction` counts what was done by hand that a verb could have done, at paths that already run; it blocks nothing, and it may not report a zero it did not count."
---

# The file

| file | what it owns |
|---|---|
| `lib/okf/pro/friction.rb` | the friction log: record, report, classify, clear |

# What it is, and what it is not

It is telemetry about the *tooling*, not about the knowledge base. It refuses
nothing and blocks nothing, and it is **not** one of `okf pro state`'s sources —
mixing it in would make a reader's payload depend on how the last session was
typed.

Nor does it register a new hook event. `.claude/settings.json` is a seeded file,
so a registration added there would never reach an existing adopter through
`upgrade`. The recorder rides the paths that already run.

# It still answers to the third clause

A recorder that fails quietly reports a clean session it never observed, which
is the contract's third clause broken by something that is not even a check.
So:

* a failed write leaves `MARKER` (`okf-pro-friction.unavailable`) behind, and
  `available?` is asked directly rather than inferred from an empty log;
* an unwritable `.tmp/` is confessed, not shrugged at;
* an unparseable line is reported rather than skipped.

The argument is [telemetry-does-not-lie](/contract/telemetry-does-not-lie.md).

# And it may not ask for a verb that is not missing

`own_command?` recognises this gem's own invocations — including through
`WRAPPERS` (`bundle exec`, `env`, `sudo` and the rest) — so `okf pro capture`
is not recorded as friction against `okf pro capture`. `covered_by` and
`verb_covered?` decide whether a row names something a verb would actually
answer: a shell redirect's honest answer is `SHELL_ANSWER` — Edit or Write,
because the trust guards read a tool event and a redirect is none. The session
banner counts only the rows a verb would answer, and `--issue` prints nothing
when nothing was recorded.
