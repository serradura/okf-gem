# Prompt: search — retrieve knowledge without paying for the whole bundle

Retrieval matters as much as curation: a bundle nobody can query cheaply is
dead weight. The discipline is progressive disclosure (spec §8): every step
pays a few hundred bytes to decide what the next step reads, and full bodies
are read last, and only the winners.

1. **Know what exists.** `list_bundles` names every bundle this server holds —
   slug, concept count, type and tag rollups. Slugs are the `bundle` argument
   every other tool takes; omit `bundle` on `search` (or pass `"*"`) to span
   every bundle at once through one shared index, so scores stay comparable.
2. **Ingest the map and decide where to look.** `dirs` is the skeleton: every
   directory with the weight living at and below it. *You* do the semantic
   matching here — the question names a meaning, the map names directories;
   connect them by judgment, not string equality. When one looks right, `index`
   with `dir` buys its authored index body and concept listing (titles +
   descriptions) for the price of one directory.
3. **Cut across with `search` when the question is lexical.** An exact symbol,
   an error code, a column name, a phrase — things structure won't surface.
   Terms AND together and are matched **literally against raw text** by
   default, so an exact query means what it looks like: a phrase, a dotted
   version (`7.2.0`), an underscored identifier (`customer_id`), a mid-word
   fragment (`ustomer`) and a word written in `backticks` all match the way you
   typed them.

   **Match the engine to the shape of the query, not to habit** — the default
   answers most of them, and the two engines fail in opposite directions:

   | Your query is | Reach for | Because |
   |---|---|---|
   | an identifier, version, path, phrase, or anything in `` `backticks` `` | *nothing — the default* | matched literally; the index shatters all of these |
   | a mid-word fragment (`ustomer`) | *nothing — the default* | an infix is not a token, so the index cannot reach it |
   | a pattern (`err_[a-z]+_409`) | `regexp: true` | Ruby regexp over raw text; still the scan |
   | a partial word (`dedup` → `deduplication`) | *nothing — the default* | substring covers prefixes, and suffixes and infixes too |
   | a theme, where you want the best match to lead | `engine: "index"` | BM25+ ranks by relevance, not by summed field weight |
   | possibly mistyped | `fuzzy: true` | edit distance 0.2 × term length — the index's alone |

   **`fuzzy` is an engine switch, not a mode.** It routes to the index, so a
   call that only wanted a typo forgiven also gets token matching, shattered
   identifiers and unfindable code spans. Fix the spelling and stay on the
   default when you can. The payload's `engine` field names which engine
   actually answered.

   Scope any of them with what the map taught you: `dir`, `type`, `tag`, `in`.
   A `dir` that names no directory is *refused*, never answered with zero —
   a refusal means fix the spelling; `total: 0` means the terms are absent.
   Matches carry the fields they hit, and the snippet often *is* the answer.
   Searching several bundles, read each row's `bundle` slug before following
   an id home.
4. **Read only the winners.** `read_concept` takes a result row's exact `id`
   and returns the file verbatim — that concept, not its folder, never the
   whole tree. Follow its links (§6) one hop at a time; check `log` when
   freshness matters.
5. **Answer, then surface the friction.** Cite the concept ids you used. This
   server never writes — if the answer was missing, stale, or needlessly hard
   to find, say so: retrieval friction is curation signal, and fixing it
   belongs to the bundle's maintainers through the okf skill and CLI.

Anti-patterns, each a real token bill:

- **The dump.** Paging `catalog` to read a bundle whole, or `index` with
  bodies over the entire tree, costs more than every step above combined.
  Planning a multi-hop traversal needs at most `graph` with view `"minimal"`.
- **Mechanical synonym retries.** The finder is exact by default; *you* are
  the fuzzy layer. When terms miss, learn the bundle's vocabulary — the type
  and tag rollups in `list_bundles`, or `graph`'s type and tag indexes — and
  re-ask in its own words. `fuzzy` forgives a *typo*, not a wrong vocabulary.
- **Argument-shopping a query that found nothing.** Cycling `fuzzy`, then
  `engine: "index"`, then `regexp` over the same terms is guessing, and each
  engine fails differently enough that one eventually returns *something* —
  which is how a wrong answer gets found. Zero matches is usually a vocabulary
  result, not an engine result: go back to the map and the rollups. Reach for
  a different engine when you can say which property of the query needs it.
