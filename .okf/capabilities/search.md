---
type: Capability
title: Ranked text search (search)
description: Deterministic ranked retrieval over concept metadata and bodies — the browser page's search brought to the CLI, extended to bodies.
resource: lib/okf/bundle/search.rb
tags: [read, cli, json]
timestamp: 2026-07-13T12:00:00Z
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

# Deliberately not fuzzy

No stemming, no typo distance, no synonyms. The consuming agent is the fuzzy
layer: synonyms and vocabulary drift are judgment over the index map, not string
distance. Determinism is what keeps a result explainable — each row says exactly
which fields hit.

# The retrieval eval keeps the economics honest

The suite plants a fact in a fixture bundle and asserts that the progressive
path — index skeleton, one search, one body — answers it in **under 25% of the
bytes** of the full graph dump. The [companion skill](agent-skill.md)'s search
playbook rides that path, so its economics stay true by construction.

# Citations

[1] [lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/search.rb) — the pure core: weights, ANDing, snippets.
[2] [test/integration/cli/cli_search_test.rb](https://github.com/serradura/okf-gem/blob/main/test/integration/cli/cli_search_test.rb) — the retrieval eval.
