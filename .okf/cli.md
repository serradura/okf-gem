---
type: Component
title: The okf command-line front end
description: The only layer that parses argv, prints, writes files, and decides exit codes.
resource: lib/okf/cli.rb
tags: [cli, shell, registry]
timestamp: 2026-07-17T04:00:00Z
---

# Overview

`OKF::CLI` is the executable's front end and the single place where the gem
touches the outside world for a command: it parses `argv`, prints, writes files,
and chooses the exit code. Every library class beneath it just returns data — the
CLI is the [shell half](design/core-shell-split.md) of the architecture. Output
streams are injected (`out:`/`err:`) so the whole surface is driven in tests
without a real terminal or socket — which is what lets this layer, the product a
user actually touches, be [proven end to end](design/integration-first.md) rather
than by proxy.

# Subcommands

Dispatch is a single `case` on the first argument. The verbs fall into three
groups:

| Group | Verbs | Notes |
|-------|-------|-------|
| Judge | `validate`, `lint`, `loose` | [validate](capabilities/validator.md) and [lint](capabilities/linter.md) answer different questions and stay separate. |
| Read | `search`, `index`, `catalog`, `files`, `types`, `tags`, `stats`, `graph` | the [browser views as text](capabilities/read-views.md), plus the `index` map and [ranked search](capabilities/search.md). |
| Act | `server`, `render`, `registry`, `skill` | boot or statically [render](capabilities/graph-server.md) the [graph server](capabilities/graph-server.md); curate the [bundle registry](registry.md); install the [agent skill](capabilities/agent-skill.md). |

Plus `version` / `--version` / `-v` and `help` / `--help` / `-h`.

# `server` reads its mode from how many dirs you give it

One verb covers three intentions, and the argument count is the whole interface —
no `--hub` flag, no second verb:

| Invocation | Serves |
|------------|--------|
| `okf server <dir>` | that bundle at `/` — the classic single server |
| `okf server <dir> <dir>…` | those bundles behind a [hub](capabilities/graph-server.md), ephemerally (the first is the default); nothing is registered |
| `okf server` | the [registry](registry.md), at its chosen default |

Passing dirs never writes to the registry: an ad-hoc look at two bundles side by
side should not enrol them in the user's durable list. Registering is always the
explicit act of `okf registry set`.

`registry` is an umbrella verb — `list`, `set`, `del`, `default`, `rename` — over
one persistent file, and `--home DIR` (or `$OKF_HOME`) points every one of them at
a different registry, which is what keeps the tests off the real `~/.okf`.

# Every output names its bundle, in the identity the caller used

Two keys, one meaning each: `bundle` is always a directory, `slug` always a
registry slug. Name a bundle by [@ref](registry.md) and the answer comes back in
that identity — `OKF lint — @handbook (/path/to/one)`, and
`{ "bundle": "/path/to/one", "slug": "handbook", … }`. The point is an agent
holding several bundles at once: an output that names only a path forces it to
remember which invocation produced which answer, and remembering is where a
model confabulates. [Cross-bundle search](capabilities/search.md) goes further
and maps every slug to its dir in the head, so a hit resolves to a file with no
second call.

A bundle named by *path* carries no slug, deliberately. It may not have one, and
inventing a name it was never given would imply a registration that does not
exist — while looking one up would cost a registry read on every plain-dir run,
which is the laziness that keeps unregistered use free. The identity the caller
used is the identity they get back.

# @refs: the registry names bundles for every verb

Wherever a `<bundle-dir>` goes, `@slug` resolves a [registered bundle](registry.md)
and bare `@` the registry's default — one resolution seam (`resolve_ref`, shared
by the positional parsers and search's ref list), inherited by all verbs at once,
so `okf lint @handbook` works from any directory. Refs read `$OKF_HOME`, and
`--home` steers them wherever a verb offers it (`registry`, `server`, `search`) —
which is why the not-registered error names the registry file it consulted, so a
mismatch self-diagnoses rather than reading as "never registered".

A leading `@` always means the registry (`./@name` keeps an odd directory
reachable), the registry file loads only when a ref appears, and an explicit ask
fails hard: an unknown slug, a registered-but-gone directory, or a malformed
registry is a usage error whose message names the next move, never a silent skip.
The normalization is the subtle part — a ref is normalized exactly as
registration normalized it, so `@One` finds the bundle from dir `One`, but
*without* the placeholder that minting a slug from a basename needs: a name has
to come out of `slugify("!!!")`, and nothing may come out of a lookup, or `@***`
would quietly resolve to whatever bundle is slugged `bundle`.

`server` refs carry their registered slug to the mount, and reserve it before any
plain dir's basename is deduped — otherwise `server ./two @two` would hand `/b/two/`
to the *unregistered* directory and a bookmark would open the wrong graph. (The
first argument still lands at `/`; the registry's chosen default applies only to a
bundle-less run.) [`search`](capabilities/search.md) is the one verb that *merges*
several bundles into one answer — several refs, or `--all`.

# Exit codes

The contract every verb keeps:

| Code | Meaning |
|------|---------|
| `0` | success — including a bundle with lint findings (`lint` is advisory) |
| `1` | a non-conformant bundle (`validate`) or a `lint --fail-on warn` threshold crossed |
| `2` | usage error — unknown command, missing directory, bad flag, a bad `-o` path, or a *second* bundle |

That last one is the subtle member: only [`search`](capabilities/search.md) merges
several bundles and only `server` mounts them, so a second bundle handed to any
other verb is a question it cannot answer. Reading the first and dropping the rest
would answer confidently about a bundle nobody asked about, which is why it is a
usage error rather than a convenience — the same reason a bad `-o` path is exit 2
and not a backtrace.

# Best-effort reads

`graph`, `server`, `render`, and the read views are best-effort under §9: a file with
invalid frontmatter is kept in `bundle.unparseable`, skipped, and *noted on
stderr* (so JSON on stdout stays clean) rather than aborting the whole command.
One bad file never breaks the rest. Run [validate](capabilities/validator.md) for
the details of what was skipped.

# Citations

[1] [lib/okf/cli.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli.rb) — the dispatch, option parsing, and printers.
