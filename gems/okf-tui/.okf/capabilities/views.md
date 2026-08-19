---
type: Capability
title: The Six Views
description: What each screen answers, whether it is about one bundle or the whole scope, which keys reach it, and which reader supplies its numbers.
tags: [views, keyboard, capabilities]
timestamp: 2026-08-19
---

# The catalogue

`App::TABS` is the source of truth for this table, and a test holds the two
together.

| view | key | answers | reads |
|---|---|---|---|
| `bundles` | `1` | what can I open, which is active, which is the default — the registry's groups, and all registry config | `Workspace` |
| `browse` | `2` | what is in the bundle, in reading order — `index.md`, `log.md`, then each directory | `Model#rows`, `#dirs` |
| `search` | `3` | which concept covers X, across *every bundle in scope*, ranked together | `Workspace#search` |
| `graph` | `4` | what shape is its knowledge — narrowed by type, tag or dir | `Model#graph`, `#types`, `#tags` |
| `health` | `5` | is it legal, well curated, well structured — findings left, standing right | `Model#validation`, `#lint`, `#hubs`, `#dir_traffic`, `#dir_arcs` |
| `help` | `6` | the keys | — |

# Which of them are about *one* bundle

`browse`, `graph` and `health` are `SINGLE_BUNDLE_VIEWS`: they follow the
**active** bundle, and they have nothing to show when none can be read. `search`
follows the **scope** instead — a different, independent axis, so you can read
one bundle while searching all of them. `bundles` is where both are set.

That two-axis model is the thing most likely to be got wrong by a new view, and
[cross-bundle-scope](/interaction/cross-bundle-scope.md) is the argument for it.

# The two behaviours every view inherits

`health` and `help` are `CONTENT_VIEWS` — a single scrolling page rather than a
selectable list, which changes what the arrow keys mean.

`bundles`, `browse` and `graph` are `FILTERABLE_VIEWS` — `/` starts typing, and
the filter belongs to the view, so switching away drops it. When a browse filter
matches nothing, `Enter` carries the term to search, because that is the query
the reader was already making:
[filter-escalates-to-search](/interaction/filter-escalates-to-search.md).

A seventh view is a real cost on a six-tab bar, and one has already been
withdrawn for not earning its tab. Before adding one, check that an existing
view with a key the reader already has does not answer the same question.
