# Playbook: search — retrieve knowledge without paying for the whole bundle

Reached by `search <query…>` — the query is everything after the verb; given no
query, ask what to find. Retrieval matters as much as curation: a bundle nobody
can query cheaply is dead weight. The discipline is progressive disclosure
(spec §6): every step pays a few hundred bytes to decide what the next step
reads, and full bodies are read last, and only the winners.

1. **Just run it — no presence probe.** Point the finder at a path or an `@slug`
   (a registered bundle; bare `@` = the default). Only a shell `okf: command not
   found` means install (→ [doctor](doctor.md)); with no CLI possible at all, read
   the root `index.md` then each relevant area's `index.md` by hand. No bundle in
   the cwd? `okf registry list` names the registered ones — address them by
   `@slug`, don't hunt sibling directories.
2. **Ingest the map and decide where to look.** `okf index <dir|@slug> --no-body` is
   the skeleton: every directory with its concept count, types, tags, children.
   *You* do the semantic matching here — the question names a meaning, the map
   names areas; connect them by judgment, not string equality. When an area
   looks right, `okf index <dir> --area <name>` buys its authored index body and
   listing (titles + descriptions) for the price of one directory.
   <!-- rule:okf-search-map-first -->
3. **Cut across with the finder when the question is lexical.** An exact
   symbol, an error code, a column name, a phrase — things structure won't
   surface — go to `okf search <dir> <terms>` (terms AND together, matched as
   whole tokens or prefixes). **Reach for `--engine scan` when the query is exact
   by nature**: a phrase, a dotted version (`7.2.0`), an underscored identifier
   (`customer_id`), a mid-word fragment (`ustomer`), or anything likely written
   in `backticks` — a code span indexes as one glued token, so the default misses
   it entirely. Add `-e` on top for patterns (`err_[a-z]+_409`). The default
   tokenizer splits on punctuation, so those queries otherwise match far more
   loosely than they read, and ranking does not reliably float the true hit to the
   top. A search that returns suspiciously few rows for an identifier is the
   signal. <!-- rule:okf-search-exact-identifiers -->
   Scope it with what the map taught you:
   `--area billing`, `--type Decision`, `--tag idempotency`, `--in body`.
   Matches rank by where they hit, and the snippet often *is* the answer.
   When the answer may live in another registered bundle, span them — leading
   @slugs (`okf search @handbook @notes <terms>`) or `@all` for every registered
   one — and read the per-row bundle slug before following an id home.
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
- **Mechanical synonym retries.** The finder is exact by default; *you* are the
  fuzzy layer. When terms miss, learn the bundle's vocabulary — `okf tags
  <dir>`, `okf types <dir>` — and re-ask in its own words. `--fuzzy` forgives a
  *typo*, not a wrong vocabulary, so it is the wrong reach for this.
