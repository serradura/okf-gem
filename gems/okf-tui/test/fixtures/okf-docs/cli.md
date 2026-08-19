---
type: Component
title: The okf command-line front end
description: The only layer that parses argv, prints, writes files, and decides exit codes.
resource: lib/okf/cli.rb
tags: [cli, shell, registry]
timestamp: 2026-07-17T14:00:00Z
---

# Overview

`OKF::CLI` is the executable's front end and the single place where the gem
touches the outside world for a command: it parses `argv`, prints, writes files,
and chooses the exit code. Every library class beneath it just returns data — the
CLI is the [shell half](design/core-shell-split.md) of the architecture. Output
streams are injected (`out:`/`err:`) so the whole surface is driven in tests
without a real terminal or socket — which is what lets this layer, the product a
user actually touches, be [proven end to end](design/integration-first.md) rather
than by proxy. Even `--help` keeps that contract: rather than the `exit`
OptionParser's own handler would call — printing past those streams to the
process's stdout — each parser writes its banner to `out:` and throws `:help`
back to `run`, which returns the caught status, so a command's help is driven
and asserted like the command itself.

# Subcommands

Dispatch is a single `case` on the first argument. The verbs fall into three
groups:

| Group | Verbs | Notes |
|-------|-------|-------|
| Judge | `validate`, `lint`, `loose` | [validate](capabilities/validator.md) and [lint](capabilities/linter.md) answer different questions and stay separate. |
| Read | `search`, `index`, `catalog`, `files`, `types`, `tags`, `stats`, `graph` | the [browser views as text](capabilities/read-views.md), plus the `index` map and [ranked search](capabilities/search.md). |
| Act | `server`, `render`, `registry`, `skill` | boot the [graph server](capabilities/graph-server.md) or write it as a [static file](capabilities/render.md); curate the [bundle registry](registry.md); install the [agent skill](capabilities/agent-skill.md). |

Plus `version` / `--version` / `-v` and `help` / `--help` / `-h`.

# `server` reads its mode from how many dirs you give it

One verb covers three intentions, and the argument count is the whole interface —
no `--hub` flag, no second verb:

| Invocation | Serves |
|------------|--------|
| `okf server <dir>` | that bundle at `/` — the classic single server |
| `okf server <dir> <dir>…` | those bundles behind a [hub](capabilities/graph-server.md), ephemerally (the first is the default); nothing is registered |
| `okf server` | the [registry](registry.md), its first entry still on disk at `/` |

Passing dirs never writes to the registry: an ad-hoc look at two bundles side by
side should not enrol them in the user's durable list. Registering is always the
explicit act of `okf registry set`.

`registry` is an umbrella verb — `list`, `set`, `del`, `default`, `rename` — over
one persistent file, and `$OKF_HOME` points every one of them at a different
registry, which is what keeps the tests off the real `~/.okf`.

One lever, not two. An earlier design also carried a `--home DIR` flag, which had
to be remembered on the three verbs that offered it and forgotten on the eleven
that did not — a flag whose whole job was to name a location the env var already
named. `$OKF_HOME` composes where a flag cannot: it reaches every verb at once
without being typed, it survives into a subprocess, and if the directory ever
holds more than `registry.json` it keeps meaning the same thing.

# Every output names its bundle, in the identity the caller used

Two keys, one meaning each: `bundle` is always a directory, `slug` always a
registry slug. Name a bundle by [@slug](registry.md) and the answer comes back in
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

# @slug: the registry names bundles for every verb

Wherever a `<dir>` goes, `@slug` resolves a [registered bundle](registry.md)
and bare `@` the registry's default — one resolution seam (`resolve_ref`, shared
by the positional parsers and search's ref list), inherited by all verbs at once,
so `okf lint @handbook` works from any directory. They read `$OKF_HOME`, which is
why the not-registered error names the registry file it consulted, so a mismatch
self-diagnoses rather than reading as "never registered".

A leading `@` always means the registry (`./@name` keeps an odd directory
reachable), the registry file loads only when a ref appears, and an explicit ask
fails hard: an unknown slug, a registered-but-gone directory, or a malformed
registry is a usage error whose message names the next move, never a silent skip.
The normalization is the subtle part — a slug is normalized exactly as
registration normalized it, so `@One` finds the bundle from dir `One`, but
*without* the placeholder that minting a slug from a basename needs: a name has
to come out of `slugify("!!!")`, and nothing may come out of a lookup, or `@***`
would quietly resolve to whatever bundle is slugged `bundle`.

A `server` `@slug` carries its registered slug to the mount, and reserves it before any
plain dir's basename is deduped — otherwise `server ./two @two` would hand `/b/two/`
to the *unregistered* directory and a bookmark would open the wrong graph. (The
first argument still lands at `/`; the registry's own order applies only to a
bundle-less run.) [`search`](capabilities/search.md) is the one verb that *merges*
several bundles into one answer — several @slugs, or `@all`.

`@all` is a ref, not a flag, and only `search` expands it. That restraint is the
point: through the shared seam, `okf lint @all` would resolve to one bundle when
one is registered (and lint it) and to two when two are (exit 2 by the
[second-bundle rule](#exit-codes)) — the same command's meaning tracking the size
of the registry, which is the silent-wrong-answer shape the rule exists to stop.
So every other verb refuses `@all` by name instead, and `all` is reserved as a
slug so the refusal can never be wrong.

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

`graph`, `server`, `render`, and the read views are best-effort under §9: a file
the reader cannot use is kept in `bundle.unparseable`, skipped, and *noted on
stderr* (so JSON on stdout stays clean) rather than aborting the whole command.
One bad file never breaks the rest. Run [validate](capabilities/validator.md) for
the details of what was skipped — the note counts, `validate` names each file and
why.

Two causes reach that bucket, and the tolerance has to cover both or it is not a
posture but a coincidence: frontmatter that will not **parse**, and a file that
will not **open** at all. The second was the gap — an unreadable file threw its
errno out of the reader, and since the read is the one path every verb shares, a
single locked file took the whole bundle down through all of them, as a backtrace
under an exit code that claims *non-conformant*. It is one unusable file. It
reports as one, under §9.1, naming the file and the errno.
<!-- rule:okf-read-best-effort -->

The boundary: `Path.join_under!` still raises. A path leaving the bundle root is
not a bad file — it is a bundle lying about its shape, and best-effort is
tolerance for damage, never for a claim.

# Citations

[1] [lib/okf/cli.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli.rb) — the dispatch, option parsing, and printers.
