---
type: Constraint
title: Search engines are adapters, and the facade owns the row
description: One facade over N retrieval engines, selected by the capabilities a query needs — with a shared conformance suite standing in for the oracle rule that multiple engines made impossible.
resource: lib/okf/bundle/search.rb
tags: [architecture, search, extensibility, testing]
timestamp: 2026-07-18T19:00:00Z
---

# Overview

[`OKF::Bundle::Search`](../capabilities/search.md) is a **facade**, not an
implementation. It owns everything that defines what a result *is*, and delegates
only the retrieval question to an engine:

| The facade owns | An engine answers |
|---|---|
| entry points (`.call`, `.across`) | which documents match |
| document assembly and the `"<slug>\0<id>"` key | how well each matches |
| the row hash and its key order | which fields the terms hit |
| the snippet window, `area`, the final sort | which matcher to point the snippet at |

The split exists because an engine that built its own rows could disagree about
what a match *means* — two engines, two answer shapes, and a merged ranking that
looks sorted and compares nothing. Putting the row in the facade makes that
unrepresentable rather than merely discouraged.

# Selection is by capability, not by name

An engine declares three things — `id`, `capabilities`, `available?` — and the
router picks the first available engine offering **every** capability the query
requires, default first, then registration order:

```
-e            requires :regexp  →  Search::Scan
--fuzzy       requires :fuzzy   →  Search::Index
neither                         →  the default (:index)
nothing qualifies               →  UnsupportedQuery, which the CLI makes exit 2
```

There is deliberately **no `--engine` flag**. The flags a user already reaches
for are the selector, so there is no second vocabulary to keep consistent with
the first, and no way to ask for an engine that cannot answer the question. The
cost is that the choice is invisible, which is why
[`okf search --help`](../cli.md) carries the engine attribution: it is the only
surface left to explain it on.

`available?` is not decorative. The base gem's two engines are always available —
`minifts` is a hard dependency with no native extension — but an addon backed by
SQLite can fail to build, and the rule it inherits is that a broken build
*degrades* rather than crashes. An engine whose store is missing answers
`available? == false`; it never raises at query time.

# `Search.register` is the second extension point

```ruby
OKF::Bundle::Search.register(engine)  # append-only, idempotent by id
OKF::Bundle::Search.engines           # frozen snapshot, preference order
```

Append-only and idempotent by `id`, so a double `require` cannot double the
registry and an addon cannot quietly displace a built-in. Capabilities outside
the declared vocabulary are refused at registration — a typo like `:regex` would
otherwise present as "my engine is silently never chosen".

The built-ins register at *their* load, an addon at *its*, so `require "okf"`
yields exactly `[Index, Scan]`. A clean-subprocess probe pins that — the same
guard that keeps the [CLI shell out of the library load](core-shell-split.md) —
because a `gem install` that silently changed what `okf search` answers would be
a surprise nobody opted into.

# The conformance suite replaced the oracle rule

The earlier plan for addon search was that `Bundle::Search` defines semantics and
every backend must return "the same match set, modulo ranking order". **That rule
cannot survive more than one engine.** The index and the scan disagree about match
sets by design — a phrase, an infix, a dotted identifier — so naming either the
oracle would make the other a bug.

What replaced it is narrower and actually holds: a shared conformance suite,
included by one test class per engine, asserting only what must be true
regardless of engine — the row shape and key order, ANDed terms, what `fields:`
restricts, the ordering, the empty answers, and that `across` keeps same-id
concepts distinct. Capability-gated blocks run only for engines declaring the
capability, so an engine earns its own semantics by declaring them rather than by
being excused from a rule.

A registered engine with no conformance class is itself a test failure. That is
the property the oracle rule was reaching for and could not express.

This follows the same discipline as the [core/shell split](core-shell-split.md):
a boundary is only real when a test fails on crossing it, and it is checked the
same way [integration first](integration-first.md) checks the CLI — against what
a caller actually gets, not what an internal returns.

# Citations

[1] [lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/search.rb) — the facade: registry, router, row, snippet, sort.
[2] [test/unit/bundle/search/engine_conformance.rb](https://github.com/serradura/okf-gem/blob/main/test/unit/bundle/search/engine_conformance.rb) — the contract every engine satisfies.
[3] [test/unit/bundle/search/accepted_losses_test.rb](https://github.com/serradura/okf-gem/blob/main/test/unit/bundle/search/accepted_losses_test.rb) — the precision the index gives up, pinned from both sides.
