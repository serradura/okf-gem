---
type: Capability
title: MCP server (okf-mcp)
description: The kernel's proven capabilities projected onto the Model Context Protocol — fourteen read-only tools, concepts as resources, and the two consuming prompts, for any MCP-capable agent host.
resource: okf-mcp/lib/okf/mcp/server.rb
tags: [mcp, serve, agent, registry, search]
generated:
  by: human:maintainer
  at: 2026-08-14T12:00:00Z
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

The `status`/`trust` filters keep one rule across surfaces by *where they
narrow*: on `catalog` they run through the kernel's `Bundle::RowFilter` like
every row filter, but on `search` they resolve **through the catalog** — a
search row carries what the engine matched on, and the §5 families are not
among it, so handing them to the row filter would read as absent and match
nothing. The tool instead asks the catalog which ids qualify, per bundle, and
keeps the rows that survive: the same predicate underneath, so a `trust` that
narrows `catalog` narrows `search` identically. The first cut was the
two-line fix — add the keys to the filter — and it shipped the worse failure:
a schema that accepts the argument and an answer that silently matches
nothing.

The `tags`/`types`/`stats` trio closes the read-view gap the parity audit
priced, on the kernel-first path: `Bundle#tag_groups` and `Bundle#stats`
were extracted from the CLI verbs so the counting rules have one home, and
both shells consume them. `files` is deliberately not a tool — `index`'s
per-directory listing and `catalog`'s projection already carry its whole
answer, and it would have been the first tool whose answer two others hold
whole; tool-list weight is a cost a host pays on every conversation.

The `references` tool is the §6.3 inventory the kernel's verb answers —
notably the one lens that sees a bundle's *non-markdown* files (a `.py`
attester, a `.sql` computation), with each file's citing concepts and every
pointer into `references/` that resolves to nothing, the bare-path miss named
with its leading-slash fix. It landed here the way every capability does:
kernel first (`Bundle::References`), then a thin projection.

# Identity is the kernel registry's

Every tool takes a `bundle` argument that is a **registry slug** — the same
identity `@slug` resolves at the CLI and `/b/<slug>/` mounts on the
[hub](bundles-manager.md). One name across all four surfaces, and a slug is
only ever a key into the served map: no tool opens a path from a request.

**One name across the fourteen tools, too**, which took a second pass. `search` is
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
shared `Search.prepare` corpus per searched set for index queries, built on
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
the served set whenever the set *moves* now — not on every request, which took
the residency and corpus locks and queued every unrelated call behind whatever
index build another host was paying for — since an operator repointing entries
otherwise retains every root the registry has ever named — and the prune
reaches the corpus cache too, which pins the same parsed bundles plus a
prepared index over each: its LRU evicts only on an index query, so a
scan-only workload would have held a dropped root's corpus forever. And the on-disk
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
date-grouped entries per file (§9's own structure) with each file's `total` and
`returned`, which cut that answer to 13,491 bytes and a whole eval session in
half. The split stays here rather than in the kernel because bounding for a
context window is this surface's problem alone — the [graph
server](graph-server.md)'s Log panel wants the whole file and scrolls it. The
general shape: **a bound that counts containers instead of contents reads as
bounded and is not**, which is the same false-comfort class as a capability
declared by default.

That shape kept producing instances, each found by review rather than by use.
§9 fixes no heading level, so a log grouped under `###` is conformant and the
`## ` split cannot see it: the file came back *whole* under `total: 0`, an
unbounded read advertising itself as empty, and `limit` could not reach the
path at all. The first fix counted it as one indivisible entry cut by size —
and left the same read alive one shape over, where a whole history under a
single `## ` heading split into one "entry" and came back whole behind a
`total: 1` that read as bounded. The byte budget `limit` scales now caps
*every* answer, announced with `truncated` — inventing a boundary would be
inventing a format, but declaring a bound is only honest. Both of the answer's
units keep their word: the budget is enforced in **bytes** as announced (a
character count let a multibyte log through at up to 4x the cap, silently),
and `returned` is recounted from what *survived* the cut, never claiming an
entry whose heading the cut removed. A scaffolded title with no entries yet
reports the zero it holds instead of one entry of history that does not exist
— wherever whitespace put the title. And `total` itself meant two things: the rows
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
The set consulted is `Bundle#directories` — the same list the `dirs` rows are
built from — because the refusal's own advice is "orient with dirs", and a
first cut that derived it from the raw file list accepted directories `dirs`
refuses to list (one holding only a file the reader skipped). One question,
one source, on both sides of the refusal. The message carries the one nuance
the source cannot: a directory standing on disk but holding only unparseable
files is refused as exactly that — "holds only files the reader could not
parse", pointing at `validate` — because "no directory" would be false about
the filesystem and sends the caller off to re-spell a name that was correct
when the fix is repairing the files.

Kernel refusals become
`isError` tool responses carrying the kernel's own sentences; the tool
descriptions carry the skill's retrieval doctrine (orient with `dirs`, descend
with `index`, search for pointed questions, read only winners), because they
are the only playbook a Desktop host ever sees. Two prompts — the consuming
pair — restate that doctrine in full, in tool vocabulary; why only two is the
section below.

# One entry point: the `okf mcp` verb

The gem is separate because it has to be: the `mcp` SDK's floor is 2.7 against
the kernel's 2.4, and it brings five transitive dependencies to a tool whose
runtime set is deliberately three. Neither fact argues for a separate
*command*, and conflating the two questions is what left `okf mcp` unbuilt at
0.1.0. The [extension seam](../design/extension-points.md) exists precisely so
the dependency stays on the addon's side of the line: `okf-mcp/lib/okf/plugin.rb`
registers the verb, the baseline names nothing, and a 2.4 machine simply cannot
install the gem (`required_ruby_version` refuses). The kernel floor is the same
kind of promise and easier to break silently: the gemspec must name the okf
release that ships every API the shell calls (`>= 1.13`, for
`Bundle#directories`), because the monorepo's path pin satisfies any floor and
hides one that lies — the declared minimum admitted a kernel the code raised
NoMethodError against, and no test can notice without installing the old gem.
So the verb is free, and what
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

Three obligations come with routing a protocol server through a CLI dispatcher.
**Stdout stays pure**: the kernel's dispatch path writes plugin diagnostics and
unknown-verb refusals to stderr, never stdout, and `MCP::CLI` now takes the
human channel as a parameter instead of writing to `$stdout` — so the verb
honors the injected streams and no boot line can corrupt the first frame. A
spawned test asserts the first byte on stdout is a JSON-RPC frame. **The SDK
loads inside `#call`**, not at the top of the plugin file, because discovery
requires that file for `okf help` and for every unknown verb; a `require` at
load time would charge every one of those runs for a server nobody asked for.
**The exit contract is structural.** Boot and serve are separate phases in the
verb itself: everything that can fail as an operator mistake — argv, the
registry, the HTTP bind — happens under a rescue that answers exit 2 with one
line, and nothing raised while serving can reach it. On stdio the two hang-up
errnos are the session's normal end, exit 0; any other mid-serve errno
propagates as the crash it is. Diagnostics are best-effort throughout, because
a dead stderr must not decide a server's fate: before the split, the boot
rescue's own print re-raised EPIPE as a backtrace for a normal hang-up, and a
lost `--http` boot line read as a clean exit 0 for a server that never started
accepting.

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

# The prompts are the consuming pair, in tool vocabulary

The prompt surface took three cuts to find its principle. Four of the
[skill's](agent-skill.md) nine playbooks shipped first, selected by nothing
better than their names resembling tools. The second cut served all eight
(everything but `doctor`, whose premise — install the CLI — anything reaching
this server has disproved), on the argument that **a prompt is instructions,
not a capability**: the writing a playbook describes is done by the host's own
tools, so the read-only posture excluded nothing.

That argument is true and was still the wrong test, because it never asked
*whose* instructions they were. Every playbook speaks in `okf …` invocations,
half dead-end a CLI-less host at "install the CLI first" (`menu`'s step 1
literally ends "Everything below needs the CLI"), six link on into a reference
tree this server does not serve — and five teach authoring, a mission every
tool here refuses. To the host this surface exists for, they taught a
vocabulary it cannot use toward work it cannot do. The right test is the
mission: this server makes a client an expert **consumer** of bundles, so it
serves the two consuming playbooks — `okf-search` and `okf-consume`, in
`SKILL.md`'s own order — rewritten against the tools (`list_bundles`, `dirs`,
`index`, `search`, `read_concept`, `log`, `graph`), with the engine doctrine
and the anti-patterns carried over in the tools' argument spellings. A test
pins the voice: every tool the texts name must exist on the wire, and no
backticked CLI invocation survives.

The rewrite has a real cost, accepted knowingly: the texts are okf-mcp's own
(`lib/okf/mcp/prompts/`), no longer read from the installed kernel, so a
doctrine change in the skill must be carried here by hand. What it bought is
that the prompts work where they are served — and it dissolved the version-skew
failure mode the old path carried, where a kernel that renamed a playbook left
this server advertising a file that is gone. Authoring stays with the skill,
installed where a filesystem and the CLI actually are.

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
