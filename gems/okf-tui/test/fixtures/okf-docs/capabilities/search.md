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

Everything a token index cannot represent is something the tokenizer already
split or normalized away. Four losses, all measured, all recovered by `-e`:

| Query | Scan (`-e`) | Index (default) |
|---|---|---|
| `"dedup key"` as one argument | contiguous only | two tokens ANDed — matches words paragraphs apart |
| `7.2.0` | one string | tokens `7`, `2`, `0` — matches "0 downtime, 7 regions, 2 zones" |
| `customer_id` | one string | `customer` + `id` — matches "the customer table has an id column" |
| `ustomer` | finds Customers | nothing: an infix is not a token |

The tokenizer splits on whitespace **and punctuation**, which is why a dot and an
underscore both shatter an identifier. `-e` is the recovery for all four, and it
is the one query language an inverted index cannot answer: a pattern is matched
against raw text by linear scan, over the same fields with the same weights. The
two are different query languages rather than two dials on one, so `-e` and
`--fuzzy` together is a usage error (exit `2`) instead of a silently dropped flag.
Note the edge: `-e` is a *pattern* language, so `7.2.0` still matches `7x2y0` —
the literal wants `-e '7\.2\.0'`.

All four are recovered by `--engine scan` (raw text, literal) or `-e` (raw text,
pattern) — see the engines section below.

**Ranking does not contain the loss.** This capability previously claimed the
true hit still ranks first, so the cost was only extra rows below the answer.
That is false, and the pinning tests found it: BM25 normalizes by field length,
so a short body dense in `7`, `2` and `0` outscores the concept that actually
says `7.2.0`. On this very bundle, `okf search .okf 7.2.0` ranks
[the Ruby floor](../design/ruby-floor.md) — a page full of `2.4`, `2.6`, `3.x` —
**above** [the graph server](graph-server.md), the one concept naming the
version. The mitigation is real but partial, which is precisely why `-e` has to
stay reachable and documented rather than merely present.

# Engines are adapters, chosen by what the query needs

`OKF::Bundle::Search` is a facade over N engines, not one implementation with a
branch. It owns everything that defines what a *result* is — documents, the row
and its key order, the snippet window, the final sort — and delegates only "which
documents match, how well, and where":

| Engine | Capabilities | Scoring |
|---|---|---|
| `Search::Index` (default) | `fuzzy`, `prefix` | BM25+, corpus-relative |
| `Search::Scan` | `regexp` | summed field weights, absolute |

Selection happens two ways, and they answer different questions.

**By capability**, when the query requires something: `-e` requires `:regexp`,
`--fuzzy` requires `:fuzzy`, and a query requiring nothing gets the default.
Routing is **silent** — no note on stderr, nothing in the header, nothing in the
JSON envelope. Someone who typed `-e` does not need to be told what `-e` does on
every run.

**By name**, with `--engine`, when the query requires nothing but the *matching
model* matters. This is the case capability flags cannot express: raw-text
matching requires nothing, so there is no capability to route on.
`--engine scan` is how a caller asks for the pre-index behaviour — substring
matching over raw text, phrase, infix, dotted identifier and code span all
intact — accepting the coarser ranking that comes with it. A named engine that
cannot do what was *also* asked is an error, never a silent fallback:

```
okf search . --engine index -e 'err_[a-z]+'   # error: --engine index does not
                                              # support --regexp (try --engine scan)
okf search . --engine fts5 auth               # error: unknown search engine: fts5
                                              # (available: index, scan)
```

The two readings of a term stay separate from the engine that reads them: the
scan matches **literally** by default and `-e` opts into the pattern reading, so
`7.2.0` does not match `7x2y0` and `[draft]` is not a character class unless you
said so. Conflating those would make choosing an engine silently change what the
terms mean.

`Search.register` is the seam an addon plugs into — the second base-gem extension
point, deliberately shaped like the linter's — and
[the engine contract](../design/search-engines.md) is what keeps a registered
engine from redefining what a match is. `--engine` reads the registry at parse
time, so an addon appears in `okf search --help` without the CLI knowing it exists.

# What the default gives up, and how to get it back

The tokenizer splits on whitespace **and punctuation**, and a backtick is
Unicode `Sk` rather than `P` — so it is never split off at all. Both facts cost
recall in ways `--engine scan` recovers:

| Query | Default (index) | `--engine scan` |
|---|---|---|
| `minifts` | 2 | **5** — three concepts write it only as `` `minifts` `` |
| `json_for_script` | 1 | **3** |
| `customer_id` | matches "the customer table has an id column" | the identifier, whole |

Measured on this bundle, 2026-07-18. A word inside a code span is a token like
`` `minifts` ``, which the query `minifts` does not match — 409 such tokens here,
1,013 occurrences. That is the largest single reason `--engine scan` exists, and
why the note in `okf search --help` names backticks explicitly.

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
