---
type: Capability
title: Ranked text search (search)
description: Deterministic ranked retrieval over concept metadata and bodies — the browser page's search brought to the CLI, extended to bodies.
resource: lib/okf/bundle/search.rb
tags: [read, cli, json, registry]
timestamp: 2026-07-18T16:00:00Z
---

# Overview

`okf search <dir> <term…>` answers "which concept covers X?" for the price of a
few rows instead of a body read. The [browser page](graph-server.md) already had
search; this brings it to the [CLI](../cli.md) — the agent's eyes — and goes
further by searching bodies too. The core is `OKF::Bundle::Search`, a pure class
(guarded by the [core/shell boundary](../design/core-shell-split.md)) over the
in-memory [bundle](../model/bundle.md), so the CLI and any embedding app share
it: `OKF::Bundle::Search.call(bundle, [ "dedup", "key" ])`.

# Matching and ranking

Terms **AND** together: every term must hit at least one searched field, though
not necessarily the same one. A term is a case-insensitive substring, or a Ruby
regexp with `--regexp`/`-e`. A concept's score sums the weights of the fields
that matched — hitting a field twice does not stack:

| Field | Weight |
|-------|--------|
| `title` | 5 |
| `id` | 4 |
| `tags` | 3 |
| `type`, `description` | 2 |
| `body` | 1 |

Rows order by score descending, then id. A match in `description` or `body`
carries one bounded context snippet (~44 characters each side of the first hit);
the other fields need none because they already appear whole on the row.

# It composes with the shared CLI surface

`--in FIELDS` restricts the searched fields; the `--type`/`--area`/`--tag`
filters and `--fields`/`--except` projections shared with the
[read views](read-views.md) apply unchanged. It is an advisory read: exit `0`
even with zero matches — only an invalid `--regexp` pattern is a usage error
(exit `2`).

# One question, every bundle you keep

Knowledge rarely lives in one bundle, so search is the one verb that spans the
[registry](../registry.md): leading @slugs pick bundles explicitly
(`okf search @handbook @notes auth`), and `@all` is the ref that means every
registered one. Each bundle runs the same pure `Search` and the rankings merge —
legitimate because scores are absolute term weights, not per-bundle normalized —
with every row labeled by its bundle's slug. The graph stays per-bundle on
purpose — cross-links are bundle-relative, so a merged graph would be
disconnected components — which makes search the one cross-bundle question the
CLI can answer honestly, and (for now) a capability the [hub](graph-server.md)
does not mirror.

**Asking for everything tolerates gaps; naming one bundle demands it.** `@all`
skips a registered bundle whose directory has vanished, with a note — the same
forgiveness the hub shows a stale entry — while `@handbook` fails hard, because
an explicit ask that silently answered about less than it named would be a
confident wrong answer. `@all @handbook` needs no diagnostic at all: all ⊇
handbook, so it expands, dedupes by resolved path, and answers.

That "every bundle" is a **ref rather than a flag** is what keeps the grammar
single, and it was not always so. A `--all` flag *reinterpreted the
positionals* — `okf search .okf home` read `.okf` as the bundle, `okf search
--all .okf` read it as a term — the same slot meaning opposite things, decided
by a flag optparse accepts anywhere in argv. Every diagnostic around it existed
to explain that flip. As a ref, slot 1 is always a bundle identity: a directory
there is a directory, a term after it is a term, and the explanations have
nothing left to explain. Being a ref also means being normalized like one:
`@ALL` reaches `@all` through the same `Registry.normalize` that makes `@One`
find dir `One`, because a ref exempt from the grammar's one normalization is a
trapdoor. Only `search` expands `@all`, since it is the only verb
that merges; see [the CLI](../cli.md) for why the others refuse it by name.

Three edges of the grammar, all deliberate. Any leading @-arg — even one —
switches the JSON envelope from `{ bundle, slug, … }` to
`{ bundles: [{ slug, dir }, …], …, matches: [{ slug, id, … }] }`, so a consumer
branches on the form it called; the head maps each slug to its dir once, which
is what lets a row resolve to `<dir>/<id>.md` without a second lookup while
keeping long paths off every row. Projection is literal: when merging, put
`slug` in `--fields` or the row label drops and same-id concepts from
different bundles become indistinguishable. And every leading @-arg is taken
as a ref, so a literal @-term (`@babel/core`) needs a non-@ term before it or
`-e '\@term'` — the CLI notes each of these traps on stderr when it sees one.

# Deliberately not fuzzy

No stemming, no typo distance, no synonyms. The consuming agent is the fuzzy
layer: synonyms and vocabulary drift are judgment over the index map, not string
distance. Determinism is what keeps a result explainable — each row says exactly
which fields hit.

That holds for the CLI. The [browser page](graph-server.md) has since moved its
search box onto a MiniSearch full-text index — ranked, prefix, typo-tolerant —
so the two answer differently on purpose: a human scanning a graph wants the
near miss, an agent citing a row wants the exact field that hit. The divergence
is a waypoint rather than the destination — the browser is pinned to the same
`7.2.0` build the Ruby `minisearch` port tracks, so adopting that port here is
what would let one engine serve both without giving up an explainable row.

# The retrieval eval keeps the economics honest

The suite plants a fact in a fixture bundle and asserts that the progressive
path — index skeleton, one search, one body — answers it in **under 25% of the
bytes** of the full graph dump. The [companion skill](agent-skill.md)'s search
playbook rides that path, so its economics stay true by construction.

# Citations

[1] [lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/search.rb) — the pure core: weights, ANDing, snippets.
[2] [test/integration/cli/by_dir/cli_search_test.rb](https://github.com/serradura/okf-gem/blob/main/test/integration/cli/by_dir/cli_search_test.rb) — the retrieval eval.
