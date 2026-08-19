---
type: Decision
title: Only gates answer at the hook door
description: The CI verbs are not checks, and accepting one as a check name would report clean without ever reading the event.
---

# The whitelist

`HOOK_NAMES` is `CHECKS.keys` plus `session-context`, and nothing else. The CI
verbs — `audit`, `records`, `snapshot`, `unverified` — are deliberately not in
it, so `okf pro hook audit` is a refusal rather than a run.

They read like checks. They ask the same invariants, they live in the same CLI,
and an earlier version of this checker put all of them in one flat list of
accepted names.

# Why that list was a fail-open

A CI verb takes a **directory**. A hook check takes an **event on stdin**.
Dispatch one from the hook door and it never reads the event at all: it inspects
whatever bundle it resolves, finds nothing wrong with a tree the edit has not
touched yet, and exits 0.

Exit 0 at the hook door means *the gate ran and found nothing*. So a misspelling
in `settings.json` that happened to land on a CI verb would disarm that gate
permanently, and the only evidence would be a hook that never once complained —
which is indistinguishable from a bundle that was always clean.

That is the contract's third clause ([no check fails
silent](/contract/the-contract.md)) broken by the dispatcher rather than by a
check, and it is why the refusal names the distinction out loud instead of just
saying "unknown check": *the CI verbs are not gates and would report clean
without reading the event at all.*

# The same reasoning, one door along

`okf pro hook --help` is refused for the identical reason. Help exits 0, and a
`settings.json` that reached a help branch would be a gate switched off in
silence. It exits 2 and points at `okf pro --help`, where help actually lives.
