---
type: Capability
title: MCP server (okf-mcp)
description: The kernel's proven capabilities projected onto the Model Context Protocol — ten read-only tools, concepts as resources, and the skill's playbooks as prompts, for any MCP-capable agent host.
resource: okf-mcp/lib/okf/mcp/server.rb
tags: [mcp, serve, agent, registry, search]
timestamp: 2026-07-29T18:00:00Z
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
only ever a key into the served map: no tool opens a path from a request.

**One name across the ten tools, too**, which took a second pass. `search` is
the only one that accepts a *set*, and it announced that in the argument's name
— `bundles` against nine `bundle`s. The plural was a signal nobody could act
on: an MCP host's unknown property is refused by the schema before any okf
sentence can be written, so a caller that had just used `dirs(bundle:)` got
back "object property at `/bundle` is a disallowed additional property" and no
hint. The type already declares that it takes an array, and the
[CLI](../cli.md) spells the identity slot identically for every verb —
`okf search <dir|@slug…>` beside `okf lint <dir|@slug>`. Renamed before the
first release, on the same rule the `exe/okf-mcp` deletion followed: **a name
in the public surface is a compatibility promise from the moment it ships**,
and an alias would have been the second spelling that deletion refused. It also
retired a guard rather than adding one — a test existed only to stop the
near-miss from silently widening a search to every bundle, and the asymmetry
that made that possible is gone. Argv
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

The **identity map obeys the same rule**, which it did not at first. Served by
the [registry](../registry.md), the set of bundles was a boot snapshot — as the
[hub's](bundles-manager.md) *mounted* set still is, so this was consistency
rather than oversight — and three of the four ways it went stale were loud: an
unknown slug names what it knows. The fourth was not. An entry repointed at a
new directory kept answering from the old one under the current slug, which is
the silent wrong answer this project refuses everywhere else. The fix needed no
new mechanism, only the one already here: `stat` the registry file, re-read on
a moved fingerprint. Argv mode is untouched and not by a flag — it never
carried the kernel registry, so there is nothing to re-read and no way to
widen. A file that cannot be read or parsed keeps the last good set *without*
latching its stamp, so a transient truncation is survived rather than made
permanent until restart.

Four consequences of that rule had to be chased down after it landed. Two are
the same mistake in different clothes — **something else was still a boot
snapshot** — and two are what a *movable* served set costs a cache that was
written for a fixed one. The residency held one parsed bundle per root and never
evicted, which was bounded only by the set being fixed at boot; it is pruned to
the served set on every request now, since an operator repointing entries
otherwise retains every root the registry has ever named. And the on-disk
fingerprint is taken once per root per request rather than per ask: freshness is
a question *between* requests, and asking it three times inside one cost three
full-tree walks under the residency lock (`search` on the index engine measured
three, now one). Both hang off the request seam, which is the two public
entry points and deliberately not `handle_request` — the JSON-RPC layer treats
the handler block as a lookup and calls what it returns afterwards, so a wrapper
there encloses nothing. The resource list was computed once and handed to the SDK as a
fixed array, so a bundle registered afterwards was never advertised and a
removed one stayed advertised until a read of the very URI we published came
back "unknown bundle" — it is derived per `resources/list` now, at the one
`stat` per bundle it always cost. And the *stamp itself* was taken after the
boot read rather than before it, so a write landing in between was recorded as
already-seen: entries from before it, fingerprint from after, and nothing to do
until some further write moved the fingerprint again. Booting stamps nothing
now; the first call re-reads. A stamp is a claim about a file you have already
read, and it may never be taken later than the read it labels.
Federation runs through `Search.across`/one corpus, so BM25 scores are
comparable by construction. The engine doctrine is the CLI's exactly: scan by
default, `engine: "index"` opt-in, `fuzzy` implying the index, `regexp` on the
scan, incompatible pairs refused naming the fix.

# Bounded outputs, honest errors

Every list output carries a visible `total` — `search` caps at 20 rows,
`catalog` pages at 200, rollups cap at 25 with `other_*` remainders, `index`
descends one level unless asked, and `graph` serves three views that never
carry bodies (the dump anti-pattern stays unreachable).

**A `total` bounds nothing unless it counts the thing that grows.** `log`
carried one from the start and was the one unbounded read on the surface: it
counted log *files*, so `total: 1` sat above this repo's entire 119,863-byte
history — the answer to "what changed recently" scaling with the project's age
rather than the question. The pre-release ROI eval found it, and on the same
recommended path the instructions name. It now returns the newest three
date-grouped entries per file (§7's own structure) with each file's `total` and
`returned`, which cut that answer to 13,491 bytes and a whole eval session in
half. The split stays here rather than in the kernel because bounding for a
context window is this surface's problem alone — the [graph
server](graph-server.md)'s Log panel wants the whole file and scrolls it. The
general shape: **a bound that counts containers instead of contents reads as
bounded and is not**, which is the same false-comfort class as a capability
declared by default.

That shape had two more instances, both found by review rather than by use.
§7 fixes no heading level, so a log grouped under `###` is conformant and the
`## ` split cannot see it: the file came back *whole* under `total: 0`, an
unbounded read advertising itself as empty, and `limit` could not reach the
path at all. It counts as the one indivisible entry it is now, cut by size with
`truncated` saying so — inventing a boundary would be inventing a format, but
declaring a bound is only honest. And `total` itself meant two things: the rows
matched in `catalog`/`search`, the whole bundle's directory count in
`dirs`/`index`. Each defensible alone; as a set it made the larger number read
as rows withheld from a tool that takes no limit. One key, one question.

**An empty answer that reads like a real one is the same failure wearing
zero.** `dirs` and `index` refused a `dir` naming no directory; `catalog` and
`search` answered `total: 0` to it. Worst for `root` — the spelling the
[CLI](../cli.md) and the [skill](agent-skill.md) both teach — where an agent
asked for the bundle root, was told zero, and reported that the bundle root
holds nothing. Every tool taking a `dir` refuses one now, and across bundles the
refusal is a fact about the searched *set*: a directory one of three bundles has
still filters, because otherwise the ordinary cross-bundle ask would break.

Kernel refusals become
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
emits `structuredContent` beside the text. Declaring a shape is also what
exposes what the shape leaves out — `search` named its query, its bundles and
its rows, and not the **engine that answered**, which `fuzzy` selects without
being asked. Nothing in the result recovers it: the scan's integer count and
the index's BM25 float both round to a number. So a miss under the index's
[tokenizer](search.md) — a shattered identifier, a documented recall hole —
was indistinguishable from a fact the bundle does not hold, which is the
silent wrong answer again in its quietest form. The schemas are proven rather than
asserted — the suite runs every tool through every variant with the SDK's
result validation switched on, while production leaves it off, because a schema
bug should fail a test rather than turn a working tool into a runtime error.

The honesty rule the `readOnlyHint` annotations already followed turned out to
be broken at the handshake: passing no `capabilities:` inherited the SDK's
default, which announced `resources` while `resources/list` answered `[]`,
`logging` that nothing emitted through, and `listChanged` on lists nothing
notifies about. Declaring them explicitly is the fix, and the general shape is
the same one the containment hole taught: **a default you did not choose is
still a claim you made.**

`listChanged` stays undeclared even now that the resource list genuinely moves,
because the test is whether anything *notifies*, not whether anything changes.
A host that re-lists sees the current set; one that caches the boot listing is
stale until it asks again. Declaring the capability is what would fix that, and
it waits on something actually sending the notification — announcing it first
would only invite a host to wait for one that never comes.

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

What a prompt carries is its **steps**, not the craft behind them. Six of the
eight link on into the skill's reference tree — `authoring.md`, the templates,
the spec — and this server serves bundles, not the skill, so a host without
file access cannot follow them; `okf-produce` leans hardest on that and is
thinnest without it. Serving the tree would need a URI scheme of its own,
because `okf://<slug>/<id>` would read `okf://skill/…` as a bundle slugged
`skill`. That a *separate* scheme is available at any time and collides with
nothing is what makes the decision genuinely deferrable — unlike the argument
name above, waiting reserves nothing and costs nothing. The silence was not
deferrable, so the README says it: the gap is stated at the first release
rather than found by whoever pulls the prompt.

# Transports and posture

One server definition, two transports: stdio (default — each host spawns its
own process, boot line on stderr) and `--http` — Streamable HTTP in stateless
JSON mode on the WEBrick the kernel already ships.

**What the Host allowlist is, and is not.** It feeds the SDK's DNS-rebinding
protection: a browser walked into this port by a page the reader never meant to
give it to. It is *not* access control, because a client that is not a browser
sets `Host` to whatever it likes, and there is no authentication behind it. So
`--bind 0.0.0.0` publishes every served bundle to anything that can reach the
port, and the boot line warns in those words rather than printing a URL that
reads as safe to share. Selling the allowlist as the security story would be
the same overselling the [extension seam](../design/extension-points.md)
refuses for the `okf-*` prefix — the false confidence is worse than no rule.

Binding publicly is nonetheless allowed, matching the
[graph server](graph-server.md): its read surface follows any bind too, and
only the *write* surface refuses, with **no flag that says otherwise**. The
first release is read-only by construction (`readOnlyHint` on all ten tools),
so it sits entirely on the permitted side of that line. The capture write-back
— one narrow tool through the kernel's validating writer, opt-in per bundle —
inherits the refusal verbatim when it lands: **loopback only, no override.**
Recorded here while the write surface does not exist, because that is the only
moment the boundary is free to draw.
