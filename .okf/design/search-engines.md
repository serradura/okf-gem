---
type: Constraint
title: Search engines are adapters, and the facade owns the row
description: One facade over N retrieval engines — the scan by default, the index when a query needs it or names it — with a shared conformance suite standing in for the oracle rule that multiple engines made impossible.
resource: lib/okf/bundle/search.rb
tags: [architecture, search, extensibility, testing]
timestamp: 2026-07-24T12:00:00Z
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
| the snippet window, `top_dir`, the final sort | which matcher to point the snippet at |

The split exists because an engine that built its own rows could disagree about
what a match *means* — two engines, two answer shapes, and a merged ranking that
looks sorted and compares nothing. Putting the row in the facade makes that
unrepresentable rather than merely discouraged.

# Selection is by capability, then by name

An engine declares three things — `id`, `capabilities`, `available?` — and the
router picks the first available engine offering **every** capability the query
requires, default first, then registration order:

```
--fuzzy       requires :fuzzy   →  Search::Index
-e            requires :regexp  →  the default already offers it
neither                         →  the default (:scan)
nothing qualifies               →  UnsupportedQuery, which the CLI makes exit 2
```

Capability routing came first and was, for one release, the *only* selector —
"the flags a user already reaches for are the selector" — on the reasoning that a
second vocabulary would have to be kept consistent with the first. That was
wrong in one specific way, and the gap is worth recording: **a capability flag can
only express what a query needs, not which matching model answers it.** Raw-text
matching requires nothing; BM25 ranking requires nothing. Neither can be asked for
by requiring something, so under capability routing alone the non-default engine
was unreachable at any price.

`--engine NAME` is the override that closes it, and naming an engine is an
override rather than a hint: an engine that cannot do what was *also* asked is an
error (`UnsupportedQuery` naming the engine), never a silent fallback, since
falling back would answer a different question than the one posed. An unknown
name lists what is registered.

# The default is the scan

The default engine is `Search::Scan`, and the reason is that a CLI process builds
an index, asks one question and exits — a build with a single query to amortize
it over. End to end: 3.00 s against 0.24 s at 1,000 concepts, 0.83 s against
0.18 s at 250. The build is ~95% of the index path's cost at every size.

Recall settles it. Raw-text matching has no tokenizer, so it has none of the
tokenizer's holes: MiniSearch splits on `\p{Z}\p{P}`, and a backtick is `Sk`
while `$` is `Sc`, so a word inside a code span is stored as the token
`` `minifts` `` and the query `minifts` does not match it. On this bundle that
was 2 hits where the scan found 5. A loss that returns plausible rows while
omitting most of the answer is the worst kind to have on a path nobody opted
into.

What the index gives back — BM25+ ranking, prefix matching, `--fuzzy`, and
parity with the browser page — is now reached by asking. That the *page* still
runs MiniSearch means the CLI and the page rank identically only under
`--engine index`; the claim used to be unconditional and is not any more.

This has now been revisited on the server side. An engine may expose `prepare`,
which builds whatever it would otherwise build per call and hands it back; a
`Search::Corpus` holds one per engine id and passes it as `prepared:`. The scan
declares no `prepare` and is handed none — the seam is opt-in, so adding it broke
no engine and required nothing of an addon. The arithmetic above still holds for
the CLI, which has one query to amortize over; it does not for a server, which
has every keystroke after boot. See
[the search capability](../capabilities/search.md).

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

**What the conformance suite cannot do, and what covers it.** It asserts that
engines agree about the *shape* of an answer — row keys, ordering, ANDed terms,
what `fields:` restricts. It cannot notice that every engine is missing a third
of the matches, because consistency is not correctness. That blind spot is not
hypothetical: the index swap made every word inside a code span unfindable, and
the suite stayed green throughout.

`recall_test.rb` covers it by running real queries over a corpus of tokenization
hazards and measuring the index against the scan. The scan earns the oracle role
there and *only* there — for recall it is sound, because raw-text matching finds
any word that is present; for ranking and match sets the two engines disagree by
design. The test pins the known holes and fails when the set changes in either
direction, so a new hazard is named rather than discovered later in use.

This follows the same discipline as the [core/shell split](core-shell-split.md):
a boundary is only real when a test fails on crossing it, and it is checked the
same way [integration first](integration-first.md) checks the CLI — against what
a caller actually gets, not what an internal returns.

# Citations

[1] [lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/search.rb) — the facade: registry, router, row, snippet, sort.
[2] [test/unit/bundle/search/engine_conformance.rb](https://github.com/serradura/okf-gem/blob/main/test/unit/bundle/search/engine_conformance.rb) — the contract every engine satisfies.
[3] [test/unit/bundle/search/accepted_losses_test.rb](https://github.com/serradura/okf-gem/blob/main/test/unit/bundle/search/accepted_losses_test.rb) — the precision the index gives up, pinned from both sides.
