---
type: Decision
title: The Search Facade Coupling
description: The search view rides okf's engine facade — `across` for the routing, and since okf 1.11.0 a corpus prepared once and queried many times; the `fuzzy` flag is what selects the engine, and it is load-bearing in a way it does not look.
tags: [okf-coupling, search, dependencies]
generated:
  by: human:maintainer
  at: 2026-08-13
sources:
  - id: "1"
    title: "Verified 2026-07-19 in a clean `ruby:3.2-slim` container — no checkout, no bundler: `gem install okf` resolved 1.9.0, `Bundle::Search.respond_to?(:across)` → `true`, `engine_for([:fuzzy])` → `OKF::Bundle::Search::Index`. RubyGems lists okf 1.9.0 as the current release."
    resource: "Verified 2026-07-19 in a clean `ruby:3.2-slim` container — no checkout, no bundler: `gem install okf` resolved 1.9.0, `Bundle::Search.respond_to?(:across)` → `true`, `engine_for([:fuzzy])` → `OKF::Bundle::Search::Index`. RubyGems lists okf 1.9.0 as the current release"
  - id: "2"
    title: "Verified 2026-07-19 against the okf checkout: `engine_for([:fuzzy])` → `index`, `engine_for([])` → `scan`; `DEFAULT_ENGINE = :scan` in `lib/okf/bundle/search.rb`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf/lib/okf/bundle/search.rb
  - id: "3"
    title: "Measured 2026-08-13 against the registry's own five bundles (129 concepts): `across` per query 391.8 ms; with a held corpus 16.2 / 13.0 / 12.0 / 14.4 ms after the first. On the six test fixtures (36 concepts): 62–80 ms against 2.7–3.0 ms."
    resource: "Measured 2026-08-13 against the registry's own five bundles (129 concepts): `across` per query 391.8 ms; with a held corpus 16.2 / 13.0 / 12.0 / 14.4 ms after the first. On the six test fixtures (36 concepts): 62–80 ms against 2.7–3.0 ms"
  - id: "4"
    title: "Reproduced 2026-07-18: `ruby -Ilib` outside bundler loaded okf 1.8.0 from the mise gem path, `Bundle::Search.respond_to?(:across)` → `false`, search returned 0 hits for a term the checkout finds. Under `bundle exec` the same query returned 1 hit (\"orphan\") and 11 (\"registry\")."
    resource: "Reproduced 2026-07-18: `ruby -Ilib` outside bundler loaded okf 1.8.0 from the mise gem path, `Bundle::Search.respond_to?(:across)` → `false`, search returned 0 hits for a term the checkout finds. Under `bundle exec` the same query returned 1 hit (\"orphan\") and 11 (\"registry\")"
  - title: "`lib/okf/tui.rb` — `OKF::TUI.search_capable?`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui.rb
---

# Overview

The search view calls `OKF::Bundle::Search.across`, okf's engine facade, which
merges several bundles into **one** ranked corpus.

**This has shipped.** `across` was unreleased when the view was built — `okf`
1.8.0 on RubyGems had no such method — but okf **1.9.0 carries it**, verified
from a clean install with no checkout and no bundler in sight.[^1] The coupling
that shaped this file is resolved.

The coupling is deliberate, because per-bundle indexes would be a different and
worse product: BM25 weighs a term by how rare it is *in the corpus*, so indexing
each bundle separately scores the same match differently depending on which
bundle it came from. One index makes one corpus, and cross-bundle scores that
can be compared are the whole point of the view. See
[cross-bundle-scope](/interaction/cross-bundle-scope.md).

# `fuzzy: true` is what selects the engine

okf has since made the facade route between engines, and the **BM25 index is no
longer the default** — a plain search runs the regexp scan, because a one-shot
CLI cannot amortize an index build. okf-tui still gets the index, but only as a
consequence of asking for a capability the scan does not have:

```ruby
OKF::Bundle::Search.across(pairs, terms, fuzzy: true)
```

The registry picks the default engine first and falls through to one that can
answer, so `fuzzy` is what routes this to minifts.[^2] That makes the flag
load-bearing in a way it does not look: **dropping `fuzzy: true` would silently
change the engine**, and with it the ranking — no error, no missing method, just
different results and no BM25 scores. The screen would still work.

Unlike the CLI, the TUI is long-lived and searches repeatedly, so paying for the
index is the right trade here even though it is the wrong default there.

# Long-lived means the corpus is held, not rebuilt

Which was the point, and for a release the code did not act on it. `Search.across`
rebuilds **everything** per call — the documents and the index over them — and the
TUI called it on every submitted query. okf 1.11.0 had already added the pair for
this exact case, and uses them in its own server:

```ruby
corpus = OKF::Bundle::Search.prepare(pairs)          # once, per scope
OKF::Bundle::Search.with(corpus, terms, fuzzy: true) # per query
```

Measured over five registered bundles, 129 concepts: **392 ms** for the first
query, then **12–16 ms**. Before, every query paid the 392 ms.[^3] It is the same
arithmetic okf used to justify the opposite default — an index build amortized over
one query is a bad trade, and over many it is the whole point.

Two details that are not obvious from the API:

- **No `engine:` is passed to `prepare`.** That argument only moves the index build
  *earlier*; there is no boot here to move it into, and a session that never
  searches should not pay to index bundles nobody opened. The index is built lazily
  on the first query and memoized inside the corpus, which is okf's behaviour, not
  something arranged here.
- **A held corpus is a snapshot, and staleness is the failure mode.** It is keyed
  on the scoped slugs and dropped outright by `load_entries`, so a scope change or
  a reload cannot be answered from an index built over a different set. okf takes
  the same care in its hub and gives the reason: a held index outliving the set it
  was built from is a *wrong* answer rather than a slow one.

`search_test.rb` asserts the mechanism — built once, reused across queries, dropped
on scope change and on reload — and separately that the held corpus returns the
identical ranking to `across`, since this is meant to be a performance change and
nothing else.

# The floor records it

`okf >= 1.9` was the first honest floor — the version `across` shipped in, and
what made the gem publishable at all: the `okf >= 0.1` placeholder it replaced
was provably false, since no okf of that line could answer the search view.

It has moved with the kernel since, one line per capability, because each
absence fails silently rather than loudly — see
[okf-capability-drift](/decisions/okf-capability-drift.md), which records what
each one is; `prepare`/`with` above is among them. It stands at `okf >= 2.0`
today, with the `< 3` ceiling that is
[no-version-ceilings](/decisions/no-version-ceilings.md)' one earned exception.

The proof of a floor is the resolution itself, never the local suite: resolve
the *published* okf — drop the `path:` source, drop the lockfile — and run the
suite on the floor and on a modern Ruby.

# Why it still needs a boot check

The check has not become redundant — its meaning has changed. It used to guard
against an okf that had not shipped the method yet; it now guards against an
installed okf **older than the floor**, which is a thing users will actually have.

The failure mode is what makes this worth recording. `Workspace#search` rescues
a failed search into an empty result — correct for a query okf cannot parse,
badly wrong for a method that is not there, because then **every** search
answers "no matches" and the screen reads as an empty bundle rather than a
broken install.

It now checks all three methods search actually calls — `across`, `prepare`,
`with` — because a `prepare` that is not there fails the same silent way, rescued
into "no matches".

That is exactly how it presented: running the CLI via `ruby -Ilib` outside
bundler let RubyGems activate the installed `okf` 1.8.0, and search silently
found nothing.[^4] The prototype could never hit it — it put the okf checkout on
`$LOAD_PATH` directly, so it always had the unreleased method.

So the check moved out of the rescue and up to boot:

```ruby
OKF::TUI.search_capable?   # across, prepare and with — all three
```

The CLI refuses to start and exits `1`, naming **the okf file that answered** —
not the version, the file — because the usual cause is a second okf ahead of the
intended one on the load path, and a version number does not tell you that.
