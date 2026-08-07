---
type: Capability
title: MCP server (okf-mcp)
description: The kernel's proven capabilities projected onto the Model Context Protocol — ten read-only tools and the skill's playbooks as prompts, for any MCP-capable agent host.
resource: okf-mcp/lib/okf/mcp/server.rb
tags: [mcp, serve, agent, registry, search]
timestamp: 2026-07-24T12:00:00Z
---

# Overview

`okf-mcp` is the **fourth surface** beside the [CLI](../cli.md), the
[graph server](graph-server.md) and the [library API](library-api.md): a
sibling gem that maps MCP tool calls onto the kernel's library so any
MCP-capable host — Claude Desktop, Claude Code, anything speaking the protocol
— can discover, orient in, search, and read the bundles on a machine. It is
judged by one rule: it inherits the existing contracts or it is drift. Nothing
is reimplemented — every tool is a library call, and logic a tool needs that
the kernel lacks lands in the kernel first, where the other three surfaces get
it too.

# Identity is the kernel registry's

Every tool takes a `bundle` argument that is a **registry slug** — the same
identity `@slug` resolves at the CLI and `/b/<slug>/` mounts on the
[hub](bundles-manager.md). One name across all four surfaces, and a slug is
only ever a key into the served map: no tool opens a path from a request. Argv
roots are the allowlist (`okf-mcp <dir> @slug …`), slugged by the
[registry's](../registry.md) own normalization with registered slugs reserved
before basenames are deduped; no argv serves the active registry — the
project-local discovery, `$OKF_HOME` fallback and `OKF_NO_DISCOVERY` lever
included, for free, by loading through it. Groups fan out for `search` and are
refused by every single-bundle tool (the second-bundle rule by another
spelling); `"*"` tolerates a vanished directory and names the skip in the
payload, while naming one bundle demands it exist.

**The allowlist is closed at boot, and that is a property of the object, not a
promise in a comment.** Resolving an `@ref` consults the kernel registry — and
the first version then *kept* it, which quietly made a request-time door out of
a boot-time convenience: a group slug handed to `search` expanded through the
retained registry and returned bodies from bundles the operator had
deliberately not served. The fix is structural rather than a check: argv mode
does not carry the registry into the instance at all, so there is nothing to
expand through. Groups are a registry-mode identity, and in argv mode they have
already fanned out to their leaves by the time any tool runs. The general
shape, worth carrying to the next surface: **a capability held "just to answer
questions" is reachable by anything that can ask one.**

# The long-lived holder's branch

The [search](search.md) capability's lifecycle asymmetry, honored from the
other side: a one-shot CLI gets the scan, a long-lived holder gets the
prepared corpus. okf-mcp holds one parsed bundle per root, re-read only when
the on-disk fingerprint moves — bodies are always live and canonical — and one
shared `Search.prepare` corpus per served set for index queries, built on
first use and **dropped when any member's fingerprint moves** (a held index
outliving its set is a wrong answer, not a slow one — the hub's contract).
Federation runs through `Search.across`/one corpus, so BM25 scores are
comparable by construction. The engine doctrine is the CLI's exactly: scan by
default, `engine: "index"` opt-in, `fuzzy` implying the index, `regexp` on the
scan, incompatible pairs refused naming the fix.

# Bounded outputs, honest errors

Every list output carries a visible `total` — `search` caps at 20 rows,
`catalog` pages at 200, rollups cap at 25 with `other_*` remainders, `index`
descends one level unless asked, and `graph` serves three views that never
carry bodies (the dump anti-pattern stays unreachable). Kernel refusals become
`isError` tool responses carrying the kernel's own sentences; the tool
descriptions carry the skill's retrieval doctrine (orient with `dirs`, descend
with `index`, search for pointed questions, read only winners), because they
are the only playbook a Desktop host ever sees. Four prompts — `okf-consume`,
`okf-search`, `okf-maintain`, `okf-curate` — serve the
[skill's](agent-skill.md) playbooks read from the installed kernel's canonical
tree, so they version with it.

# Transports and posture

One server definition, two transports: stdio (default — each host spawns its
own process, boot line on stderr) and `--http` — Streamable HTTP in stateless
JSON mode on the WEBrick the kernel already ships, with a non-loopback bind
allowlisted so the SDK's DNS-rebinding protection stays on. Phase one is
read-only by construction (`readOnlyHint` on all ten tools); the capture
write-back — one narrow tool through the kernel's validating writer, opt-in
per bundle, loopback-only over HTTP — is the next phase, specified before the
code.
