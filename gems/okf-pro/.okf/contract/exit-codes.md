---
type: Decision
title: Exit codes
description: The hook protocol reads 0 and 2 and treats every other code as non-blocking, which inverts the repo's usual 0/1/2 convention for `hook` alone.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# What the protocol actually reads

Claude Code's hook protocol reads **0** as pass and **2** as block. Every other
exit code — including **1** — is a non-blocking error: the message is surfaced
and *the tool call proceeds*.

That is the whole reason this gem exists in the shape it does. A crash is a
pass, from the protocol's side. An interpreter that will not start is a pass. A
`LoadError` is a pass. Any defect that produces a code other than 2 is a defect
that lets the edit through.

# The deviation, and where it stops

The kernel's guide states the repo's convention as 0 ok / 1 failing bundle / 2
usage error (`@okf capabilities/validator` carries it too). `okf pro hook` cannot keep it: 1 is a code the protocol ignores, so it
is never returned. Every other verb keeps the convention.

| Verb | 0 | 1 | 2 |
|---|---|---|---|
| `hook <check>` | pass | *never* | block, crash, misconfiguration |
| `audit`, `records` | clean | findings | usage, or could not run |
| `snapshot`, `unverified` | printed | — | usage, or no bundle |
| `setup`, `upgrade`, `skill` | wrote or staged | — | usage, or refused |

# Why a crash inside `audit` is 2 and not 1

`audit` runs in CI, where 1 already means "your bundle has findings". If a crash
also exited 1, a pipeline could not tell *your bundle is broken* from *the
checker is broken* — and the second one is the case where the green runs either
side of it mean nothing. So 1 means findings and nothing else, and a crash exits
2 with a named cause.

The report-only verbs take this further: they have no findings code at all. A
non-empty `unverified` list is the truth about a corpus, not a defect in it, and
an exit code that called it a failure would pressure toward the one lie the
whole system guards against.
