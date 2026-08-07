---
type: Capability
title: MCP server (okf-mcp)
description: The kernel's proven capabilities projected onto the Model Context Protocol — ten read-only tools, concepts as resources, and the skill's playbooks as prompts, for any MCP-capable agent host.
resource: okf-mcp/lib/okf/mcp/server.rb
tags: [mcp, serve, agent, registry, search]
timestamp: 2026-07-29T12:00:00Z
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
roots are the allowlist (`okf mcp <dir> @slug …`), slugged by the
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
are the only playbook a Desktop host ever sees. Eight prompts serve the
[skill's](agent-skill.md) playbooks, read from the installed kernel's canonical
tree so they version with it — every one but `doctor`, for the reason below.

# One entry point: the `okf mcp` verb

The gem is separate because it has to be: the `mcp` SDK's floor is 2.7 against
the kernel's 2.4, and it brings five transitive dependencies to a tool whose
runtime set is deliberately three. Neither fact argues for a separate
*command*, and conflating the two questions is what left `okf mcp` unbuilt at
0.1.0. The [extension seam](../design/extension-points.md) exists precisely so
the dependency stays on the addon's side of the line: `okf-mcp/lib/okf/plugin.rb`
registers the verb, the baseline names nothing, and a 2.4 machine simply cannot
install the gem (`required_ruby_version` refuses). So the verb is free, and what
it buys is discoverability — the server appears in `okf help` under *installed
extensions* on the machines that have it, rather than waiting to be known about.

Once the verb existed, the `exe/okf-mcp` beside it was a second name for the
same `CLI.run` — one more thing to install, document, spell correctly in a host
config and keep working. It went, before the first release, while removing a
name still cost nobody anything; after one it would have been a break for every
config that spelled it. The generalizable half is the timing, not the deletion:
**an entry point is a compatibility promise from the moment it ships**, so the
window for having second thoughts closes at the first release, not at the first
complaint.

Two obligations come with routing a protocol server through a CLI dispatcher.
**Stdout stays pure**: the kernel's dispatch path writes plugin diagnostics and
unknown-verb refusals to stderr, never stdout, and `MCP::CLI` now takes the
human channel as a parameter instead of writing to `$stdout` — so the verb
honors the injected streams and no boot line can corrupt the first frame. A
spawned test asserts the first byte on stdout is a JSON-RPC frame. **The SDK
loads inside `#call`**, not at the top of the plugin file, because discovery
requires that file for `okf help` and for every unknown verb; a `require` at
load time would charge every one of those runs for a server nobody asked for.

# What the protocol offers that tools do not

Ten tools mapped the CLI's read verbs and stopped there, which left most of MCP
unused. Three additions came from comparing the surface against the protocol
rather than against the CLI.

**Resources** are the one affordance a tool call cannot provide: a host can
*attach* a document to the context itself, without the model deciding to fetch
it. Every bundle with a root `index.md` is `okf://<slug>`; every concept is
covered by the template `okf://{bundle}/{id}`. Concepts are deliberately *not*
enumerated — that would read every bundle at boot, the eager work the residency
layer exists to avoid, and would freeze a list the fingerprint check keeps
honest. The template is signage only: the SDK binds a variable to `[^/]+` and
every OKF id below the root carries a slash, so the parsing is ours. The
allowlist holds on this surface too — a URI is not a path, and a slug in one is
still only a key into the served map.

**Completions** make the template browsable instead of a shape you must already
know, and they are where containment is easiest to lose: an unserved bundle, an
unknown argument and a missing context all complete to nothing, so no
completion can confirm what argv did not serve.

**Structured output** ends the blob: every JSON tool declares its shape and
emits `structuredContent` beside the text. The schemas are proven rather than
asserted — the suite runs every tool through every variant with the SDK's
result validation switched on, while production leaves it off, because a schema
bug should fail a test rather than turn a working tool into a runtime error.

The honesty rule the `readOnlyHint` annotations already followed turned out to
be broken at the handshake: passing no `capabilities:` inherited the SDK's
default, which announced `resources` while `resources/list` answered `[]`,
`logging` that nothing emitted through, and `listChanged` on lists that never
change. Declaring them explicitly is the fix, and the general shape is the
same one the containment hole taught: **a default you did not choose is still
a claim you made.**

# A prompt is instructions, not a capability

Four of the skill's nine playbooks shipped as prompts, and the dividing line
looked like the read-only posture. It was not: what actually selected them was
that their names resembled tools. The writing a playbook describes is done by
the *host's* tools, exactly as it is when the skill is installed as a skill —
and the line had already been crossed, since `maintain` says "update bodies and
timestamp" and `curate` says "propose, then apply". Every playbook but `doctor`
is now offered, in the [skill's](agent-skill.md) own `SKILL.md` Commands table
order, so the two surfaces read alike. `doctor` stays out because reaching this
server disproves its premise: it installs the CLI.

# Transports and posture

One server definition, two transports: stdio (default — each host spawns its
own process, boot line on stderr) and `--http` — Streamable HTTP in stateless
JSON mode on the WEBrick the kernel already ships, with a non-loopback bind
allowlisted so the SDK's DNS-rebinding protection stays on. Phase one is
read-only by construction (`readOnlyHint` on all ten tools); the capture
write-back — one narrow tool through the kernel's validating writer, opt-in
per bundle, loopback-only over HTTP — is the next phase, specified before the
code.
