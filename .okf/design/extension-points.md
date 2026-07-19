---
type: Constraint
title: Three extension points, one idiom
description: Linter checks, search engines and CLI verbs all register the same way — append-only, idempotent by id, so an addon can never displace a built-in.
resource: lib/okf/cli.rb
tags: [architecture, cli, plugins, search, registry]
timestamp: 2026-07-19T18:00:00Z
---

# Overview

The gem grows by registration, not by editing. Three seams take addons, and they
are deliberately the same shape:

| Seam | Registers | State |
|------|-----------|-------|
| `Search.register` | a [search engine](../capabilities/search.md) | shipped |
| `CLI.register` | a [command](../cli.md) — a verb `okf` answers to | shipped |
| `Linter.register` | a [lint check](../capabilities/linter.md) | planned |

One idiom, in all three: **append-only, idempotent by id**. A second
registration of an id already present is a no-op, so a double `require` cannot
double the registry and **an addon cannot quietly displace a built-in**. What
each admits is checked at registration rather than at use — a capability outside
the frozen vocabulary, a command that does not answer the duck type — so a
malformed addon fails where it is *installed*, not the first time somebody
reaches for it.

# Discovery is a convention, not a list

A gem extends the CLI by putting `okf/plugin.rb` on its load path and
registering from it. That is the entire contract. `Gem.find_latest_files` finds
it; nothing here names it.

The alternative — this gem keeping a list of the addons it knows about — was
rejected because it inverts who depends on whom. Every new addon would cost an
okf release, and the base gem would carry the names of things it does not
contain. Search set the precedent already: `--engine` reads the engine registry
at parse time, so an addon appears in `okf search --help` **without the CLI
knowing it exists**. A test greps `cli.rb` for addon names to keep it that way.

The one-way dependency is what makes it safe: `okf-tui` depends on `okf`, `okf`
depends on nothing of `okf-tui`, and discovery is by convention rather than
declaration — so there is no cycle to resolve.

# Lazy, because a one-shot CLI cannot afford eager

Discovery costs about 11ms on the [2.4 floor](ruby-floor.md). Small, and still
not worth paying on every run: `okf lint` resolves its verb against the registry
and dispatches **without scanning at all**. Only two paths pay — an unknown verb,
which has to look before it can fail, and `okf help`, which has to know
everything by definition.

This is the same arithmetic that made the scan the default
[search engine](search-engines.md): a process that loads a bundle, answers one
question and exits has nothing to amortize a fixed cost over. A CLI that refuses
to build an index for a single query should not pay for discovery to answer a
verb it shipped with.

Laziness has a second effect, unplanned but welcome. An addon that tries to claim
a built-in's verb is not merely refused — running that verb never loads it at
all. The refusal still has to hold for `okf help`, which does scan, and it does:
registration keeps the built-in and records the rejection.

# A broken addon is skipped, not fatal

The same [best-effort posture](../cli.md#best-effort-reads) the reader takes with
an unparseable file. A plugin that raises on load is caught, collected, and
reported on **stderr** — so a `--json` run's stdout stays a clean machine
substrate — and every other verb still works. One addon that will not load must
not cost a user their `okf lint`.

# What a command is

A `CLI::Command` subclass answering four questions about itself — `.id`,
`.group`, `.help_rows`, `.hidden?` — and one about a run: `#call(argv)`,
returning the exit status. Privacy is the boundary, which is the one idea worth
taking from Thor without taking Thor: `#call` is the whole public surface, so a
helper added to the base can never become a verb by accident.

There is no second, lesser interface for an addon. A plugin implements exactly
what a built-in does, because a seam only the base gem can use is not a seam.

# Why not Thor

Thor is the obvious reach, and the [Ruby 2.4 floor](ruby-floor.md) closes it:
Thor 1.3+ requires Ruby >= 2.6, and only the EOL 1.2.2 line accepts 2.4. Pinning
an old line for everyone is the mistake
[no version ceilings](../design/runtime-dependencies.md) already records as
having broken things once.

It would also be a fourth [runtime dependency](runtime-dependencies.md), which is
a design decision to be challenged rather than a convenience — and it would buy
little. What the CLI needed was a *registry*, not an option-parsing DSL; it
already has `optparse` from the stdlib, plus a help, exit-code and
stream-injection contract that Thor would fight rather than serve.

What Thor's ecosystem *did* supply is the structure: a base class holding the
shared surface, one file per command group, and privacy as the command boundary.
Those are ideas, and ideas are free.

# Citations

[1] [lib/okf/cli.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/cli.rb) — `register`, `load_plugins`, the lazy dispatch, and `PLUGIN_FILE`.
[2] [lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/search.rb) — the idiom this one copies.
[3] Verified 2026-07-19 on `ruby:2.4.10` (RubyGems 3.0.3): `Gem.find_latest_files` is present and answers in ~11ms; the full suite is green on the floor.
[4] Thor's ruby_version on RubyGems, 2026-07-19: 1.4.0 and 1.3.2 declare `>= 2.6.0`; 1.2.2 declares `>= 2.0.0`.
