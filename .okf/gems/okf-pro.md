---
type: Component
title: okf-pro — the enforcement layer
description: A profile of OKF plus the gates that hold a bundle to it — `okf pro setup` writes an agent's knowledge repository, and `okf pro hook` refuses an edit that breaks it.
resource: gems/okf-pro
tags: [gem, enforcement, agent, hooks, scaffold, trust]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: gems/okf-pro
    resource: https://github.com/serradura/okf/tree/main/gems/okf-pro
  - title: gems/okf-pro/README.md
    resource: https://github.com/serradura/okf/blob/main/gems/okf-pro/README.md
---

# Overview

`okf-pro` is the **fifth surface** beside the CLI (`@okf cli`), the
graph server (`@okf capabilities/graph-server`), the library API (`@okf capabilities/library-api`) and the
MCP server (`@okf-mcp design/the-tool-set`), and the first one that **writes** rather than
reads. It answers a question the others cannot: an agent that keeps notes
accumulates a folder, and what turns a folder into a memory is not a better
format — it is a small number of invariants that something actually enforces.

Two halves. `okf pro setup` generates an agent's knowledge repository: a
blank-slate bundle plus the governance around it — Claude Code hooks behind a
fail-closed wrapper, a `pre-commit` hook that audits the staged tree, a CI
workflow, and an agent skill carrying the operating rules. `okf pro hook`
then runs one gate against one hook event, and `okf pro audit` runs the same
invariants again from CI.

It inherits every judgement it makes. Conformance, curation, search, the trust
tiers, where a staleness boundary falls — all of that is the
kernel's — the validator's, the linter's and the model's
(`@okf capabilities/validator`, `capabilities/linter`). What
this gem owns is the policy layered on top and the machinery that makes a gate
refuse rather than shrug.

# The contract, and why it shapes the code

> Blocking checks fail **closed**. Feedback checks fail **loud**. No check ever
> fails **silent**.

The third clause is the load-bearing one. A gate that is sometimes absent and
does not confess converts "unchecked" into "checked and fine", and there is no
later moment at which anyone finds out — the bundle was reported clean, so
nobody looks again. That is worse than having no gate at all, because "we do
not check this" produces caution and "we checked and it is fine" produces none.

Every defect the port surfaced failed in that direction, and none of them was a
wrong answer:

- **A `LoadError` from the deferred `require` is a `ScriptError`**, outside every
  rescue in okf's dispatch. Measured: process exit 1, and the hook protocol
  reads 1 as non-blocking, so the edit proceeded unchecked.
- **A `SyntaxError` in `plugin.rb`** is a `ScriptError` too, and *no gem code
  runs at all* — which retires the prototype's own claim that no wrapper could
  catch it. One can, as long as it does not `exec`.
- **A stray `okf` on `PATH` exiting 0** is indistinguishable from a clean gate
  by status alone, which is why exit-code normalisation does not close it and an
  identity marker does.
- **`Linter.call` with no options skips two clock-gated checks** and still
  reports `healthy?`. Seven of nine ran; the gate said clean; `stats[:skipped_checks]`
  said otherwise and was discarded.

The gem's own bundle at `okf-pro/.okf/` carries each of these with the
measurement behind it.

# What it enforces

Three laws, each of which exists because the failure it prevents is invisible:

- **Writing is reconciliation.** The corpus is searched before a new concept
  settles, and a contradiction that cannot be settled becomes one dated board
  line — because an unresolved contradiction is work, and work off the board is
  work nobody tracks. A collision with a concept already `status: deprecated`
  says so, so a settled question is not re-litigated.
- **The day ends with a snapshot.** One mechanical counter line under the day's
  heading, computed rather than typed, and the stop gate refuses one that
  disagrees with the board it summarises. Its value is the delta; a standing
  count is wallpaper.
- **In flight is a budget.** Five demands, and promotion requires demotion — or
  a visible, journalled renegotiation. The cap's job is not to make five right;
  it is to make overload undeniable on the day it happens.

Underneath them sits the rule the rest depends on: an agent may hold the pen for
`verified:`, but the write is routed to the owner for approval, and the approval
*is* the attestation. §5.3's tiers decide what that means — a `human:<id>`
verification discharges the read, a `process:` one leaves it owed — and four
call sites read that one rule, which is why they move together or a briefing
falls through all of them.

# The three doors

Hooks fire at the agent's tool boundary; the git hook only on a clone that
configured `core.hooksPath`; CI only on what was pushed. An edit made in an
editor and committed from a shell passes through exactly one of them, which is
why there are three and not one.

The commit door audits the **staged** tree rather than the worktree. They differ
in both directions, and each direction was a real hole: stage a broken edit and
fix the worktree without re-adding, and a worktree audit passes the broken
commit; stage a clean edit beside an unrelated dirty file, and it refuses one
that is fine.

# The boundaries it keeps

Like okf-mcp (`@okf-mcp design/the-tool-set`) and okf-tui it ships **no executable**: `okf pro`
is the only door, which is what lets the wrapper refuse anything that is not it.
Its only runtime dependency is `okf` — a gate with a dependency tree is a gate
that fails to install on the machine that needed it most — and it holds okf's
2.4 floor, which matters more here than anywhere else in the repository because
this code runs inside git hooks and CI steps on machines nobody chose.

See also: [extension points](../design/extension-points.md) for the seam it
registers through, and the monorepo layout (`@okf-eco decisions/monorepo-layout`) for
what a sibling owes the root.

# What holds it in shape

| | |
|---|---|
| Ruby floor | **2.4** — okf's, and it matters more here: this code runs inside a git hook and a CI step on machines nobody chose |
| Runtime dependencies | exactly `okf`; everything else is stdlib, because a gate with a dependency tree fails to install on the machine that needed it most |
| Entry point | no executable — `okf pro` through the kernel's plugin seam, and the scaffold's wrapper refuses any `okf` that cannot identify itself as the enforcer |
| Exit codes | the one place in this repository where **1 is non-blocking and 2 is the refusal**, because that is the hook protocol's vocabulary, not this repository's |

# Where its knowledge lives

`@okf-pro` — `gems/okf-pro/.okf/`, which ships inside the gem. It is the fullest
of the four, because this gem's defects all fail in the direction of silence and
the knowledge worth recording is where the machinery can stop asserting anything
without saying so. Its `structure/` and `capabilities/` areas are pinned by a
test.
