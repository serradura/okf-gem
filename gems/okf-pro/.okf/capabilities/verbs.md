---
type: Capability
title: The verbs — what `okf pro` already answers
description: Sixteen verbs in four families — scaffold, readers, writers, and the hook adapter — each with the module that implements it and the flags it declares.
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The catalogue

`OKF::Pro::CLI::USAGE` is the source of truth for this table, and a test holds
the two together.

| verb | argument | answers | implemented in |
|---|---|---|---|
| `setup` | `[DIR]` | create or complete an agent's brain in DIR (default `.`) | `scaffold.rb` |
| `upgrade` | `[DIR]` | rewrite the gem-owned governance files; stage the rest | `scaffold.rb` |
| `skill` | `DEST` | (re)install okf-pro's agent skill on its own | `scaffold.rb` |
| `state` | `[DIR]` | what is on the board, in one call — add `--full` for the corpus | `state.rb` |
| `board` | `[DIR]` | one row per board line: section, dates, age, links | `board.rb` |
| `audit` | `[DIR]` | every invariant at once — the CI door | `audit.rb` |
| `records` | `[DIR]` | does the staged commit rewrite a past journal day? | `records.rb` |
| `snapshot` | `[DIR]` | compute the day's counter line (prints, never writes) | `snapshot.rb` |
| `unverified` | `[DIR]` | generated concepts still awaiting the owner's read | `attestation.rb` |
| `friction` | `[DIR]` | what was done by hand that a verb could do | `friction.rb` |
| `capture` | `TEXT` | append a dated Inbox line | `writes.rb` |
| `promote` | `SEL` | Inbox or Backlog to In flight, refusing over the cap | `writes.rb` |
| `demote` | `SEL` | In flight back to Backlog | `writes.rb` |
| `journal` | `open` | create today's journal day and index it | `writes.rb` |
| `close` | `SLUG` | the three mechanical closing moves for a project | `writes.rb` |
| `hook` | `CHECK` | run one gate against a hook event on stdin | see [checks](checks.md) |

# The four families, and why they differ

**Scaffold** (`setup`, `upgrade`, `skill`) takes a *destination*, not a bundle.
It does not go through `dir_argument`: `setup` into an empty directory is the
whole point, and refusing one that holds no bundle would refuse every first run.

**Readers** (`audit`, `records`, `snapshot`, `unverified`, `state`, `board`,
`friction`) answer questions. Every one of them routes through `parse_flags`,
listed in `FLAGS` or not — because absence from that table means "accepts none",
and a verb that skips the parser hands its undeclared flag to `BundleRoot` as a
directory and reports "holds no OKF bundle" as a *finding*: a pipeline's own
typo, spelled as a broken bundle. `test/integration/cli_test.rb` pins it over
`READERS`.

**Writers** (`capture`, `promote`, `demote`, `journal`, `close`) are the shapes
with exactly one correct form. Each is additive, targeted, and refused by
`Conserve` rather than careful — see [the-writers](/structure/the-writers.md).
They go through `writer_flags` instead, because their first argument is content
and a flag there is data.

**The hook adapter** is `hook`, and it is the odd one: its exit codes are the
protocol's, not this repo's.

# Flags

Declared per verb in `CLI::FLAGS`, and the help text is read *from* that table
rather than typed beside it:

| verb | flags |
|---|---|
| `state` | `--json`, `--pretty`, `--full` |
| `board` | `--json`, `--pretty`, `--section NAME` |
| `snapshot` | `--json`, `--pretty` |
| `unverified` | `--json`, `--pretty` |
| `friction` | `--json`, `--pretty`, `--issue`, `--clear` |

Everything else accepts none, and says so.
