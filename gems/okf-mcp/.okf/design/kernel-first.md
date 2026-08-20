---
type: Constraint
title: Kernel-first — this shell restates nothing
description: Logic a tool needs lands in the kernel and is read from there, so a host's answer and a terminal's answer cannot drift apart; the corollary is that most new capabilities are not new tools.
tags: [architecture, kernel, drift, constraint]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/server.rb
---

# The rule

Every tool is a library call. Logic a tool needs that the kernel does not have
yet — `Bundle#tag_groups`, `Bundle#stats`, the cutoff grammar — is added *to
the kernel* and read from there, never implemented in this shell.

The reason is drift, and it is not hypothetical: the CLI, the graph server, the
TUI and this gem all answer the same questions about the same bundles. The
moment two of them compute an answer independently, they begin to disagree
under conditions nobody tested, and the disagreement surfaces as a user
reporting that `okf lint` and their agent say different things.

# The corollary that saves the most work

**Most new capabilities are not new tools here.** If a host needs something,
ask first whether the kernel could answer it — because if it could, the CLI and
the TUI want it too, and one kernel method serves all four surfaces.

This is also the repository's standing rule, stated at the seam: every
user-facing capability lands in the base gem first, and no addon owns semantics
the base lacks.

# What legitimately lives here

Three things, and it is a short list: **schema** (input shapes, declared output
shapes), **bounded-output arithmetic** (`total`, the log slicing, projection),
and **protocol translation** (tool errors carrying the kernel's own sentences,
both content channels, resource URIs). None of them is analysis.

If a change adds a fourth kind, that is the signal to stop and ask whether it
belongs in the kernel instead.
