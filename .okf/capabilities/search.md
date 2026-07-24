---
type: Capability
title: Ranked text search (search)
description: Full-text retrieval over concept metadata and bodies — raw-text matching by default, BM25+ token ranking on request, and explainable row by row either way.
resource: okf/lib/okf/bundle/search.rb
tags: [read, cli, json, registry, search]
timestamp: 2026-07-22T12:00:00Z
---

# Overview

`okf search <dir> <term…>` answers "which concept covers X?" for the price of a
few rows instead of a body read. The [browser page](graph-server.md) already had
search; this brings it to the [CLI](../cli.md) — the agent's eyes — and goes
further by searching bodies too. The core is `OKF::Bundle::Search`, a pure class
(guarded by the [core/shell boundary](../design/core-shell-split.md)) over the
in-memory [bundle](../model/bundle.md), so the CLI and any embedding app share
it: `OKF::Bundle::Search.call(bundle, [ "dedup", "key" ])`.

It is a **facade over two engines**. The default is a linear scan over raw text;
`--engine index` (and `--fuzzy`, which implies it) reaches a
[`minifts`](../design/runtime-dependencies.md) full-text index — the pure-Ruby
port of the MiniSearch build the browser loads, so a Ruby-built index and the
page's rank identically by construction rather than by two implementations
agreeing for as long as someone maintains both.

# Why the scan is the default

A CLI process loads the bundle, asks one question, and exits. An index build has
exactly one query to amortize it over, and it is not close:

| concepts | `--engine index` | default (scan) |
|---|---|---|
| 24 | 0.16 s | 0.10 s |
| 250 | 0.83 s | 0.18 s |
| 1,000 | 3.00 s | 0.24 s |

End to end through the CLI, 2026-07-18, Ruby 4.0.5. The build is ~95% of the
index path's cost at every size, and the gap widens with the bundle.

The headline number points the other way — `minifts` sustains
[~44–56× the query throughput](https://github.com/serradura/minifts) of a scan —
and that is the right measure for a **long-lived** index (a browser page, a
server) and the wrong one for a one-shot process. So the arithmetic above governs
the CLI only, and the server takes the other branch.

# The server holds the index, the CLI cannot

`Search.prepare` builds a **Corpus** — the documents, the key → concept map, and
the built index — and `Search.with` queries it without rebuilding. That is the
whole difference between the two callers: `okf server` prepares one at boot
(`warm_search`), so the build lands in startup where it is attributable, and
every search after it is a query alone.

| 414 concepts, served | before | after |
|---|---|---|
| boot | — | 1.39 s (once) |
| each search | 1.45 s | 0.016 – 0.052 s |

Measured 2026-07-22 through the Rack app, Ruby 4.0.5. Flat before, because each
request rebuilt the corpus it had just thrown away.

The cost is staleness: a corpus is a **snapshot**, so a body edited after it was
built is searchable only once the holder drops it — the hub does exactly that
when a registry write changes the served set. The graph is memoized on the same
terms, so this is the boundary the server already had, not a new one.

The CLI still builds per call and still defaults to the scan: a one-shot process
has nothing to amortize over, which is the asymmetry this whole section is about.

Speed is not the only reason. Raw-text matching has **no tokenizer**, so it has
no tokenizer-shaped recall holes — see below.

# Matching and ranking

Terms **AND** together: every term must hit at least one searched field, though
not necessarily the same one. Field weights are shared by both engines:

| Field | Weight |
|-------|-------|
| `title` | 5 |
| `id` | 4 |
| `tags` | 3 |
| `type`, `description` | 2 |
| `body` | 1 |

The **scan** matches a term as a literal substring anywhere in a field and scores
by summing the weights of the fields that matched — an absolute number, small and
integral. The **index** matches a whole token or a token it prefixes (`dedup`
reaches `deduplication`), and scores BM25+ with those weights riding as per-field
boost — a float, relative to the corpus.

Rows order by score descending, then slug, then id. A match in `description` or
`body` carries one bounded context snippet (~44 characters each side of the first
matched term); the other fields need none because they already appear whole on
the row.

**The row still says which fields hit.** A relevance number alone would be a
verdict an agent cannot check, so every row carries its `matched` list — read off
the engine's own per-term field record, not recomputed beside it.

# What the index gives up, and why it is opt-in

Everything a token index cannot represent is something the tokenizer already
split or normalized away. These are the reasons the scan leads:

| Query | Default (scan) | `--engine index` |
|---|---|---|
| `"dedup key"` as one argument | contiguous only | two tokens ANDed — matches words paragraphs apart |
| `7.2.0` | one string | tokens `7`, `2`, `0` — matches "0 downtime, 7 regions, 2 zones" |
| `customer_id` | the identifier, whole | `customer` + `id` — matches "the customer table has an id column" |
| `ustomer` | finds Customers | nothing: an infix is not a token |
| `minifts` | **5** concepts | 2 — three write it only as `` `minifts` `` |
| `json_for_script` | **4** | 1 |

Measured on this bundle, 2026-07-18. The tokenizer splits on whitespace **and
punctuation**, which is why a dot and an underscore both shatter an identifier.
The last two rows are a different fault: a backtick is Unicode `Sk` and `$` is
`Sc`, neither of which is `P`, so **neither is ever split off**. A word inside a
code span is stored as the token `` `minifts` ``, which the query `minifts` does
not match — 409 such tokens on this bundle, 1,013 occurrences.

That class of loss is invisible: the search succeeds, returns plausible rows, and
silently omits most of the answer. Making raw text the default is what removed it
from the path nobody opted into.

**Ranking does not contain the loss.** This capability once claimed the true hit
still ranks first, so the cost was only extra rows below the answer. That is
false, and the pinning tests found it: BM25 normalizes by field length, so a short
body dense in `7`, `2` and `0` outscores the concept that actually says `7.2.0`.
On this bundle, `okf search .okf 7.2.0 --engine index` ranks
[the Ruby floor](../design/ruby-floor.md) — a page full of `2.4`, `2.6`, `3.x` —
**above** [the graph server](graph-server.md), the one concept naming the version.

# What the index buys

Reaching for it is a real choice, not a legacy path:

- **BM25+ ranking.** Corpus-relative relevance, which absolute field weights only
  approximate. On a large or uneven bundle this is the better ordering.
- **Fuzzy matching.** `--fuzzy` is only available here — the scan has no notion
  of edit distance, so asking for it routes automatically.
- **Parity with the browser page**, which runs the same MiniSearch build. If you
  are reconciling a CLI answer with what the page shows, name the index.

That is the whole list — three things. The `prefix` capability is conspicuously
**not** a fourth, though the index declares it: a substring match already reaches
every prefix, so `dedup` finds `deduplication` under either engine while
`duplication` and `uplicat` find it under the scan alone. Prefix is what a token
index needs to catch up to raw text, not something it adds on top. Worth stating
plainly, because "prefix matching" reads like a feature the default lacks.

# Engines are adapters, chosen by what the query needs

`OKF::Bundle::Search` is a facade over N engines, not one implementation with a
branch. It owns everything that defines what a *result* is — documents, the row
and its key order, the snippet window, the final sort — and delegates only "which
documents match, how well, and where":

| Engine | Capabilities | Scoring |
|---|---|---|
| `Search::Scan` (default) | `regexp` | summed field weights, absolute |
| `Search::Index` | `fuzzy`, `prefix` | BM25+, corpus-relative |

Selection happens two ways, and they answer different questions.

**By capability**, when the query requires something: `--fuzzy` requires `:fuzzy`,
which only the index offers, so it routes there without naming it. `-e` requires
`:regexp`, which the default already provides, so it moves nothing. A query
requiring nothing gets the default. Routing is **silent** — no note on stderr,
nothing in the header, nothing in the JSON envelope.

**By name**, with `--engine`, when the query requires nothing but the *matching
model* matters. This is the case capability flags cannot express: BM25 ranking
requires no capability, so there is nothing to route on. A named engine that
cannot do what was *also* asked is an error, never a silent fallback:

```
okf search . --engine index -e 'err_[a-z]+'   # error: --engine index does not
                                              # support --regexp (try --engine scan)
okf search . --engine fts5 auth               # error: unknown search engine: fts5
                                              # (available: index, scan)
```

The two readings of a term stay separate from the engine that reads them: the
scan matches **literally** and `-e` opts into the pattern reading, so `7.2.0`
does not match `7x2y0` and `[draft]` is not a character class unless you said so.
Note the edge: `-e` is a *pattern* language, so the literal wants `-e '7\.2\.0'`.

`Search.register` is the seam an addon plugs into — the second base-gem extension
point, deliberately shaped like the linter's — and
[the engine contract](../design/search-engines.md) is what keeps a registered
engine from redefining what a match is. `--engine` reads the registry at parse
time, so an addon appears in `okf search --help` without the CLI knowing it exists.

# It composes with the shared CLI surface

`--in FIELDS` restricts the searched fields; the `--type`/`--dir`/`--tag`
filters and `--fields`/`--except` projections shared with the
[read views](read-views.md) apply unchanged. It is an advisory read: exit `0`
even with zero matches — only an invalid `--regexp` pattern, `-e` paired with
`--fuzzy`, or an `--engine` that cannot honour a flag, is a usage error (exit `2`).

# One question, every bundle you keep

Knowledge rarely lives in one bundle, so search is the one verb that spans the
[registry](../registry.md): leading @slugs pick bundles explicitly
(`okf search @handbook @notes auth`), and `@all` is the ref that means every
registered one. Every row is labeled by its bundle's slug.

**Merged rows are comparable by construction, and each engine earns that
differently.** The scan's score is absolute — summed field weights, with no
corpus term to move — so a row is worth exactly the same alone or beside two
other bundles. The index has no such luxury: BM25 prices a term by how rare it
is, so the bundles go into **one** index rather than N. A per-bundle index would
score the same match differently depending on where it came from, and
interleaving those lists would produce a ranking that looks sorted and compares
nothing. The visible consequence, under `--engine index` only, is that a score is
relative to the whole answer: the same concept is worth less searched beside two
other bundles than alone, because the term got commoner.

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

Worth knowing when you reach for it: `--fuzzy` is not merely a mode, it is an
**engine switch**. It routes to the index, so everything on this page about token
matching applies to that run — including the recall holes. A typo forgiven and an
identifier shattered arrive together.

# The retrieval eval keeps the economics honest

The suite plants a fact in a fixture bundle and asserts that the progressive
path — index skeleton, one search, one body — answers it in **under 25% of the
bytes** of the full graph dump. The [companion skill](agent-skill.md)'s search
playbook rides that path, so its economics stay true by construction.

# Citations

[1] [okf/lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/bundle/search.rb) — the facade: the row, the snippet, the sort, the engine registry and router.
[2] [okf/test/integration/cli/by_dir/cli_search_test.rb](https://github.com/serradura/okf-gem/blob/main/okf/test/integration/cli/by_dir/cli_search_test.rb) — the retrieval eval, and the default-engine pin.
[3] [okf/test/unit/bundle/search/recall_test.rb](https://github.com/serradura/okf-gem/blob/main/okf/test/unit/bundle/search/recall_test.rb) — the default has no recall holes; the index's are named and pinned.
[4] Benchmark, 2026-07-18, Ruby 4.0.5, end to end through the CLI: 0.16 s / 0.83 s / 3.00 s for `--engine index` at 24 / 250 / 1,000 concepts, against 0.10 s / 0.18 s / 0.24 s for the default scan.
