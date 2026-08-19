# `search` — ranked text retrieval (metadata + body)

Kind: reference. Answers: how terms are matched and by which engine, what the
index buys and what it silently loses, how one query spans several bundles, and
which of the two JSON envelopes comes back.

The shared contract — `@slug` refs, exit codes, `--json`, the filters this verb
also takes — is in [cli.md](../cli.md) and is not repeated here.

The browser page's search brought to the CLI and extended to bodies, so "which
concept covers X?" costs rows, not body reads. `okf search <dir> <term…>`:
terms AND together — every term must hit at least one searched field, not
necessarily the same one — matched **literally against raw text** by default, or
as Ruby regular expressions with `--regexp`/`-e` (an invalid pattern is a usage
error, exit 2). `--fuzzy` forgives typos; pairing it with `-e` is a usage error,
since a pattern is matched literally rather than by edit distance.
`--in a,b` restricts the searched fields (title, id, tags, type, description,
sources, body — `sources` is each entry's title and resource joined, so a
migrated bundle keeps the recall its `# Citations` body text used to give it);
the shared `--type/--dir/--tag/--status/--trust` filters narrow the candidates
*first*, so a search scoped by what `index` taught you stays surgical.

**The default is exact, so an exact query means what it looks like.** A phrase in
one argument (`"dedup key"`), a dotted version (`7.2.0`), an underscored
identifier (`customer_id`), a mid-word fragment (`ustomer`) and a word written in
`backticks` all match literally. This is what the scan engine buys, and it is the
default precisely because those queries are the common ones and the alternative
loses them silently. <!-- rule:okf-search-exact-identifiers -->

**`--engine index` is the other engine, and the one to reach for when ranking
matters more than exactness.** The engine is normally chosen by what the query
needs — `--fuzzy` routes to the index, anything else stays on the default scan —
and nothing is printed about the choice. `--engine NAME` overrides that for the
case the flags cannot express: a matching *model* requires no capability, so no
flag selects one. Under the index, terms match whole tokens and their prefixes
(`dedup` finds `deduplication`), rows rank by BM25+, and it is the engine the
browser page runs — so name it when reconciling a CLI answer with the page. The
cost is real: its tokenizer splits on punctuation, so identifiers shatter
(`customer_id` → `customer` + `id`), an infix finds nothing, and a backtick is
never split off at all, so a word inside a code span is unfindable — a large
silent loss, since technical prose is full of them. **Do not count on ranking to
rescue it** — BM25 normalizes by field length, so a short concept dense in `7`,
`2` and `0` can outrank the one that actually says `7.2.0`. Naming an engine that
cannot do what you also asked (`--engine index -e`) is a usage error naming one
that can. <!-- rule:okf-search-engine-choice -->

**The capabilities, and which engine has them.** An engine is selected by what
the query *requires*; only a matching model has to be named, because requiring
nothing is not something a flag can express:

| Flag | Capability | Engine | What it does |
|---|---|---|---|
| *(none)* | — | scan | literal substring over raw text; scores by summed field weight |
| `-e` / `--regexp` | `regexp` | scan | each term is a Ruby regexp, case-insensitive; invalid → exit 2 |
| `--fuzzy` | `fuzzy` | **index** | edit distance 0.2 × term length — and switches engine |
| `--engine index` | — | index | whole-token + prefix matching, BM25+ ranking, browser parity |
| `--engine scan` | — | scan | the default, spelled out |

Two consequences worth holding. **`--fuzzy` is an engine switch, not a mode**: it
carries the whole index with it, so a run that wanted one typo forgiven also gets
shattered identifiers and unfindable code spans — fix the spelling and stay on
the default when you can. And **`-e` moves nothing** now, because the default
engine already offers `regexp`; it changes how a term is *read* (pattern rather
than literal), not where it is matched. <!-- rule:okf-search-fuzzy-is-a-switch -->

`prefix` is a capability the index declares but no flag selects — it is always on
there. **It is not a reason to reach for the index**: a substring match already
covers every prefix and then some, so `dedup` finds `deduplication` under both
engines, while `duplication` and `uplicat` find it under the default only. Prefix
is what the index needs to catch up to raw text, not a capability it adds on top.
The index's real advantages over the default are exactly three — relevance
ranking, typo tolerance, and page parity.

**Search spans bundles.** Leading @refs pick several registered bundles
(`okf search @handbook @notes auth`); **`@all`** is the ref that means every one.
Rows from different bundles are ranked together and comparable, and each row
carries its bundle's slug. Under `--engine index` the bundles go into **one
corpus** — BM25 prices a term by how rare it is, so separately-ranked lists would
not compare — which makes a score relative to the whole answer: the same concept
scores lower searched beside others than searched alone. The default scan needs
no such trick — its score is absolute, so a row is worth the same either way.
This is the
cross-bundle retrieval the in-page search does not have: one question, every
bundle you keep. <!-- rule:okf-search-all -->

`@all` is a ref, not a flag, which is what keeps the grammar single: slot 1 is
always a bundle identity, so a directory there is a directory and nothing can
flip it into a term. Being a ref, it is normalized like one — `@ALL` and `@All`
name every bundle just as `@One` names the bundle registered from dir `One`. It composes accordingly — `@all @docs` expands and dedupes
(all ⊇ docs), needing no diagnostic. **Asking for everything tolerates gaps;
naming one bundle demands it**: `@all` skips a bundle whose directory has
vanished with a note on stderr, while `@docs` fails hard. `@all` is only
`search`'s: every other verb answers about one bundle, so it refuses `@all` by
name rather than letting the answer depend on how many bundles you happen to
have registered. `all` is reserved as a slug — a directory named `all/` registers
as `all-2`, `--as all` is refused, and an `all` row already in the registry file
(hand-typed, or written before the name was reserved) is read as `all-2` rather
than taken as grounds to reject the file — so `@all` is never ambiguous, and the
reservation never strands a registry it inherited. **The read normalizes every
slug** the same way registration would, so a hand-typed `"slug": "My Docs"` lists
and resolves as `my-docs`; an entry the listing shows is always an entry `@slug`,
`rename`, and `default` can name.

`--fields` projects the shape the mode actually emits: `slug` is available in
registry mode, and a usage error naming the real fields on a path-named search,
which has no slug to give. Two sharp edges: every *leading* @-arg is taken as a ref, so a literal @-term
(`@babel/core`, a Ruby `@ivar`) needs a non-@ term before it or `-e '\@term'` —
the CLI notes both traps on stderr — and any ref, even one, switches the JSON
envelope (next paragraph).

Rows rank by where they hit — title 5, id 4, tags 3, type/description 2, body 1 —
summed as an absolute score by the default scan, and carried as per-field boost
into **BM25+** under `--engine index`. Each row carries one bounded context
snippet from the strongest match that needs context (description or body). Every row still names the fields that hit (`matched`), so a result stays
citable rather than being a bare relevance number. Exact by default: the
consuming agent is the fuzzy layer — when terms miss, learn the bundle's
vocabulary from `tags`/`types` and re-ask in its own words, rather than
hammering synonyms or reaching for `--fuzzy` before you have looked. Advisory read: **exit 0 even with zero matches**.
JSON, plain-dir mode: `{ bundle, query, count, matches: [{ id, title, type,
dir, top_dir, tags, matched, score, snippet }] }`. Registry mode — any leading @ref,
`@all` or a `@group` among them (a group fans out to its member bundles) — swaps the envelope: `{ bundles: [{ slug, dir }, …],
query, count, matches: [{ slug, id, … }] }`; a parser must branch on which form
it called. The head maps each slug to its dir once, so a row resolves to
`<dir>/<id>.md` without a second lookup and without repeating a path per row.
Both are projectable with `--fields/--except`, and projection is literal — when
merging bundles, put `slug` in your `--fields` list or the row label drops and
same-id concepts from different bundles become indistinguishable. The retrieval procedure that puts this verb in sequence —
map first, finder second, bodies last — is the
[search playbook](../../playbooks/search.md).

