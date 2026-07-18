---
type: Capability
title: Ranked text search (search)
description: Full-text retrieval over concept metadata and bodies, on the same engine the browser page runs — ranked by BM25+, token-based, and still explainable row by row.
resource: lib/okf/bundle/search.rb
tags: [read, cli, json, registry]
timestamp: 2026-07-18T19:00:00Z
---

# Overview

`okf search <dir> <term…>` answers "which concept covers X?" for the price of a
few rows instead of a body read. The [browser page](graph-server.md) already had
search; this brings it to the [CLI](../cli.md) — the agent's eyes — and goes
further by searching bodies too. The core is `OKF::Bundle::Search`, a pure class
(guarded by the [core/shell boundary](../design/core-shell-split.md)) over the
in-memory [bundle](../model/bundle.md), so the CLI and any embedding app share
it: `OKF::Bundle::Search.call(bundle, [ "dedup", "key" ])`.

Underneath it is a [`minifts`](../design/runtime-dependencies.md) full-text
index — the pure-Ruby port of the MiniSearch build the browser loads. That is the
point of choosing it: the two are one engine, so a Ruby-built index and the
browser's rank identically by construction rather than by two implementations
agreeing for as long as someone maintains both.

# Matching and ranking

Terms **AND** together: every term must hit at least one searched field, though
not necessarily the same one. A term matches a whole **token** or a token it
prefixes — `dedup` reaches `deduplication` — and `--fuzzy` opts into typo
tolerance. Scoring is BM25+, with the field weights riding as per-field boost:

| Field | Boost |
|-------|-------|
| `title` | 5 |
| `id` | 4 |
| `tags` | 3 |
| `type`, `description` | 2 |
| `body` | 1 |

Rows order by score descending, then slug, then id. A match in `description` or
`body` carries one bounded context snippet (~44 characters each side of the first
matched term); the other fields need none because they already appear whole on
the row.

**The row still says which fields hit.** A relevance number alone would be a
verdict an agent cannot check, so every row carries its `matched` list — read off
the index's own per-term field record, not recomputed beside it. Ranking got
better; explainability did not get traded for it.

# What a token index gives up

An **infix**. `ustomer` used to find Customers by substring and now finds
nothing, because the engine matches tokens and their prefixes rather than
scanning raw text. `--regexp`/`-e` is the escape hatch, and it is the one query
language an inverted index cannot answer: a pattern is matched against the raw
text by linear scan, over the same fields with the same weights. The two are
different query languages rather than two dials on one, so `-e` and `--fuzzy`
together is a usage error (exit `2`) instead of a silently dropped flag.

# The index is built per invocation, and that is the current ceiling

A CLI process indexes the bundle, asks one question, and exits — so it pays a
build the old linear scan never paid and gets a single query to amortize it over.
Measured on this bundle and replicas of it (Ruby 4.0.5): **23 concepts → 55 ms
build vs 2.4 ms for a scan; 1,000 concepts → 2.2 s vs 103 ms.** Invisible at the
size real bundles are today, a real regression at scale.

This is worth stating plainly because the headline number points the other way:
`minifts` sustains [~44–56× the query throughput](https://github.com/serradura/minifts)
of the scan, which is the right measure for a long-lived index — a browser page,
a server — and the wrong one for a one-shot process. Caching a prebuilt index
(the registry is the natural home, alongside what the UI already needs) is what
converts the build into a one-time cost and collects that throughput. Until then
the swap buys ranking, prefix and fuzzy matching, and engine parity with the
browser — not CLI speed.

# It composes with the shared CLI surface

`--in FIELDS` restricts the searched fields; the `--type`/`--area`/`--tag`
filters and `--fields`/`--except` projections shared with the
[read views](read-views.md) apply unchanged. It is an advisory read: exit `0`
even with zero matches — only an invalid `--regexp` pattern, or `-e` paired with
`--fuzzy`, is a usage error (exit `2`).

# One question, every bundle you keep

Knowledge rarely lives in one bundle, so search is the one verb that spans the
[registry](../registry.md): leading @slugs pick bundles explicitly
(`okf search @handbook @notes auth`), and `@all` is the ref that means every
registered one. Every row is labeled by its bundle's slug.

**They are indexed as one corpus, not searched one at a time.** BM25 prices a
term by how rare it is, so a per-bundle index would score the same match
differently depending on which bundle it came from, and interleaving those lists
would produce a ranking that looks sorted and compares nothing. One index makes
one corpus, and the merged ranking is comparable by construction. The visible
consequence is that a score is relative to the whole answer: the same concept is
worth less when searched beside two other bundles than alone, because the term
got commoner. That is the correct behaviour, and it is what the earlier design —
absolute per-field weights that happened to compare — was approximating.

The graph stays per-bundle on purpose — cross-links are bundle-relative, so a
merged graph would be disconnected components — which makes search the one
cross-bundle question the CLI can answer honestly, and (for now) a capability the
[hub](graph-server.md) does not mirror.

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

# Exact by default, fuzzy on request

No stemming, no synonyms, and no typo distance **unless asked**: `--fuzzy` turns
on an edit distance of `0.2 × term length`, the same tolerance the browser page
passes. The default stays exact because determinism is what keeps a result
citable — the consuming agent is the fuzzy layer, since synonyms and vocabulary
drift are judgment over the index map, not string distance.

What changed is that the fuzziness is now a *flag* rather than a *fork*. The CLI
and the browser used to diverge because they ran different engines; they now run
the same one and differ only in the options each passes, which is a difference
anyone can read off one line instead of inferring from two implementations.

# The retrieval eval keeps the economics honest

The suite plants a fact in a fixture bundle and asserts that the progressive
path — index skeleton, one search, one body — answers it in **under 25% of the
bytes** of the full graph dump. The [companion skill](agent-skill.md)'s search
playbook rides that path, so its economics stay true by construction.

# Citations

[1] [lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/search.rb) — the pure core: the index build, the boost weights, the regexp scan, snippets.
[2] [test/integration/cli/by_dir/cli_search_test.rb](https://github.com/serradura/okf-gem/blob/main/test/integration/cli/by_dir/cli_search_test.rb) — the retrieval eval.
[3] [test/integration/cli/across_bundles/cli_search_test.rb](https://github.com/serradura/okf-gem/blob/main/test/integration/cli/across_bundles/cli_search_test.rb) — the one-corpus proof: the same row scores lower merged than alone.
[4] Benchmark, 2026-07-18, Ruby 4.0.5: index build 55 ms / 530 ms / 2.17 s at 23 / 250 / 1,000 concepts, against a 2.4 ms / 25 ms / 103 ms linear scan per query.
