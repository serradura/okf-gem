---
type: Component
title: Search — One Facade, Two Engines
description: The facade owns the rows, the snippets, the ranking fields and the engine registry; an engine owns only matching, declares its capabilities, and is chosen by what the query needs.
tags: [structure, search, pure, extension-point]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/bundle/search.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/bundle/search.rb` | the facade: rows, snippets, weights, the `Corpus`, and the engine registry |
| `lib/okf/bundle/search/scan.rb` | the default engine — raw-text scan, the only one that does `regexp` |
| `lib/okf/bundle/search/index.rb` | the minifts engine — BM25+, the only one that does `fuzzy` and `prefix` |

# The split

The facade decides **what a result is**: `WEIGHTS` (which field counts how much),
`FIELDS`, `SNIPPET_FIELDS`, `SNIPPET_RADIUS`, and the row shape every caller
reads. An engine decides only **which documents matched**, and says what it can
do through `CAPABILITIES`.

`Search.engine_for(required)` picks by capability, not by name: `ROUTABLE` is the
set a query can *demand* (`regexp`, `fuzzy`), `DEFAULT_ENGINE` is `:scan`, and
`UnsupportedQuery` / `UnknownEngine` are the two honest refusals. `available?`
lets an engine decline at runtime — the index engine needs `minifts` present.

`Corpus` is the cross-bundle form, behind `Search.across`.

# Why scan leads

The scan is the default because a one-shot CLI cannot amortise an index build:
3.00 s versus 0.24 s at 1,000 concepts. That is a real argument against the
`minifts` dependency and it is recorded as such — but `--fuzzy` and parity with
the graph page's browser-side ranking both still need it, and a cached index
would restore the case outright.

Parity is the subtler half: the Ruby index engine is a bit-for-bit port of the
browser's MiniSearch, pinned to the same version the page lazy-loads, so an
`--engine index` result and a search typed into the page rank identically.

# `Search.register` is an extension point

Append-only, idempotent by id, duck-type checked at registration —
**deliberately the same shape as `CLI.register`**. An engine is a module
answering `id`, `capabilities`, `available?`, `call`, and optionally `prepare`.
Adding one is a registration, not an edit to the facade.
