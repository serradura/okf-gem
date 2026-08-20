---
type: Decision
title: okf Moves, and This Breaks Quietly
description: Inventing no analysis means every answer on screen is okf's — so okf renaming a field or adding a faster path is a change to this program, and every such drift found so far failed silently rather than loudly.
tags: [okf-coupling, dependencies, testing, maintenance]
generated:
  by: human:maintainer
  at: 2026-08-13
sources:
  - title: "`okf-tui.gemspec` — the seven capabilities and the version each shipped in."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/okf-tui.gemspec
  - title: "`test/integration/dirs_test.rb` — `okf_subtree_counts`, the `okf dirs --json` oracle; and the `nested` fixture, which exists because at one directory level `dir` and `top_dir` are the same string and an assertion cannot tell them apart."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/integration/dirs_test.rb
  - title: "`test/integration/structure_test.rb` — `okf_traffic_rows`, parsing okf's human traffic table; the row count is asserted first so the comparison loop cannot pass vacuously."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/integration/structure_test.rb
  - title: "`lib/okf/tui/refs.rb` — the inherited grammar, and why it subclasses Command without ever being registered."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/refs.rb
  - title: "okf `CHANGELOG.md`, 1.12.0 \"Changed\": \"The derived `area` field is renamed `top_dir`\" — \"`area` was never the OKF spec's word (`grep -ci area SPEC.md` → 0)\"."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/CHANGELOG.md
  - title: "Measured 2026-08-13 over five registered bundles / 129 concepts: first query 391.8 ms, then 16.2 / 13.0 / 12.0 / 14.4 ms. Before, every query paid the first figure."
    resource: "Measured 2026-08-13 over five registered bundles / 129 concepts: first query 391.8 ms, then 16.2 / 13.0 / 12.0 / 14.4 ms. Before, every query paid the first figure"
---

# Overview

[invents-no-analysis](/decisions/invents-no-analysis.md) says every judgement on
screen comes from okf. The cost of that rule is not the one it looks like. It is
not that features are hard to add; it is that **okf's evolution is this program's
evolution**, and the failures arrive without a stack trace.

This file records the shape of that drift, found by catching up four okf minor
versions at once (1.9 → 1.13) and discovering that the TUI had been wrong in
production for a release without anything going red.

# Every drift found so far was silent

Four, and not one of them raised:

| What okf did | How it presented here |
|---|---|
| renamed the catalog's `area` to `top_dir` (1.12.0) | `rows.map { row[:area] }` returned `[nil]`, so **every** bundle reported `1 areas` — a wrong number that looks like a right one |
| added `Search.prepare`/`with` (1.11.0) | nothing broke; the TUI simply kept rebuilding a full-text index per query, 392 ms where 12 ms was available |
| added registry groups (1.12.0) | `registry.listing` returns bundles only, so groups were absent from the one view whose job is the registry |
| added local-registry discovery (1.12.0) | `Registry.load` without `cwd:` still worked — it just answered about a *different registry* than every other okf verb in the same directory |

Two patterns, and the second is the dangerous one:

- **A renamed field reads as nil.** Ruby hands back `nil` for a missing hash key,
  so a derived-field rename cannot fail loudly. It becomes a plausible number.
- **A new capability is invisible by construction.** Nothing is broken when okf
  adds a faster path or a new concept; the TUI is merely *less* than it was
  written to be. No test can fail for a feature nobody has written yet, which
  means the only defence is reading okf's changelog on purpose.

The renames are why the floor is now stated per capability in the gemspec, one
line each, naming the version and what fails without it. The additions are why
catching up is a periodic *task*, not an event that gets triggered.

# The defence that works: agreement, not assertion

The instinct after the `area` break is to assert the number: "this fixture has six
directories". That catches a regression in this code and nothing about drift — okf
could change what counts as a directory tomorrow and the test would keep passing
while the screen went wrong.

What works is asking okf the same question and comparing:

```ruby
# dirs_test.rb — the dir facet, against okf's own subtree column
OKF::CLI.start([ "dirs", fixture(name), "--json" ], out: out, err: StringIO.new)
```

`structure_test.rb` does the same against `okf graph --traffic`, parsing its
**human** table and matching the rendered frame row for row. Both run in-process,
so they cost milliseconds, and both fail the moment okf and this disagree about a
number — which is the actual contract, and the one an asserted constant does not
express.

Where a formula had to be reproduced (cohesion is `internal / (internal + out +
in)`, okf's arithmetic over `Bundle::Skeleton`), the agreement test is what makes
the copy safe. A comment saying "same as okf's" is a claim; the test is the check.

# Prefer inheriting a rule to copying it

Two couplings arrived in this pass, and they were resolved differently on purpose:

**The ref grammar is inherited.** `OKF::TUI::Refs` subclasses `OKF::CLI::Command`
to reach `resolve_ref_expanding`, okf's own resolver — so `@slug`, bare `@`,
`@group` fan-out, the vanished-member note and the `@all` refusal all behave
identically to `okf server`, messages and exit codes included. That is a coupling
to a **private** method, accepted because the alternative is a second copy of a
grammar with five branches and its own error strings, which is precisely the
"second argument grammar" [one-door-the-plugin-seam](/decisions/one-door-the-plugin-seam.md)
exists to prevent. `refs_test.rb` pins the seam by name, so okf moving it fails
loudly rather than quietly restoring `not a directory`.

**The `--dir` matching rule is reimplemented**, in one line
(`Model.under_dir?`), and that is not inconsistent. okf's flag handling is mostly
about *arguments a human typed* — the `root` alias, a trailing slash, case folding
— and none of it applies to a facet whose value the TUI got out of
`Bundle#directories` and whose rows carry `OKF.dir_of`. Both sides are already
okf's canonical spellings, so what is left is the set relation between two values
okf handed over. The agreement test is what holds it to okf's answer.

The rule of thumb: **inherit a grammar, reimplement a predicate, and test
agreement either way.**

# What this costs, and why it is still right

The bill is real: a periodic read of okf's changelog, a floor that has to be
raised deliberately, and a test suite that runs okf's CLI in-process to check its
own arithmetic. None of that would exist if the TUI parsed markdown itself.

It is still right, and the four drifts above are the argument. Every one of them
was a *number this program did not have to compute*, and three of the four were
okf getting better at answering it. A TUI with its own catalog would not have had
the `area` break — it would have had its own, permanently, with no upstream to
inherit the fix from.
