# Playbook: search — retrieve knowledge without paying for the whole bundle

Reached by `search <query…>` — the query is everything after the verb; given no
query, ask what to find. Retrieval matters as much as curation: a bundle nobody
can query cheaply is dead weight. The discipline is progressive disclosure
(spec §6): every step pays a few hundred bytes to decide what the next step
reads, and full bodies are read last, and only the winners.

1. **Guard once**: `command -v okf`. Missing → [doctor](doctor.md). No CLI at
   all → read the root `index.md`, then each relevant area's `index.md`, by hand.
2. **Ingest the map and decide where to look.** `okf index <dir> --no-body` is
   the skeleton: every directory with its concept count, types, tags, children.
   *You* do the semantic matching here — the question names a meaning, the map
   names areas; connect them by judgment, not string equality. When an area
   looks right, `okf index <dir> --area <name>` buys its authored index body and
   listing (titles + descriptions) for the price of one directory.
   <!-- rule:okf-search-map-first -->
3. **Cut across with the finder when the question is lexical.** An exact
   symbol, an error code, a column name, a phrase — things structure won't
   surface — go to `okf search <dir> <terms>` (terms AND together; `--regexp`
   for patterns like `err_[a-z]+_409`). Scope it with what the map taught you:
   `--area billing`, `--type Decision`, `--tag idempotency`, `--in body`.
   Matches rank by where they hit, and the snippet often *is* the answer.
4. **Read only the winners.** A match row's `id` is its file: `<dir>/<id>.md`.
   Read that file — not its folder, never the whole tree. Follow its links (§5)
   one hop at a time; check `log.md` when freshness matters.
5. **Answer, then write back.** Cite the concept ids you used. If the answer
   was missing, stale, or needlessly hard to find — a gap, a broken link, an
   index entry that should exist — switch to [maintain](maintain.md) and record
   it. Retrieval friction is curation signal. <!-- rule:okf-search-write-back -->

Anti-patterns, each a real token bill:

- **The dump.** `okf graph --json` with bodies, or `cat`-ing the tree "for
  context", costs more than every step above combined. Retrieval needs at most
  `graph --json --minimal`, and only to plan a multi-hop traversal.
- **Grep before map.** Grep cannot find the entry that is *missing*, and it
  returns line noise where `search` returns ranked concepts. Grep is the
  fallback when the CLI is absent, not the first move.
- **Mechanical synonym retries.** The finder is exact by design; *you* are the
  fuzzy layer. When terms miss, learn the bundle's vocabulary — `okf tags
  <dir>`, `okf types <dir>` — and re-ask in its own words.
