# The server views as text — `catalog`, `files`, `tags`, `types`, `stats`

Kind: reference. Answers: which of the five reads a question wants, what each
row carries, and the JSON each emits.

The filters all five narrow with — `--type`, `--dir`, `--tag`, `--status`,
`--trust` — are in [cli.md](../cli.md) with the rest of the shared contract,
since `search` takes them too.

The browser server ([serve.md](serve.md)) has Catalog, Files, Tags and Stats
panels; these
verbs reproduce them on the CLI so an agent can read a bundle without a browser.
All are advisory reads (exit 0) sharing one data source (per-concept metadata plus
in/out link degree). Add `--json` to any for a machine substrate.

- **`catalog`** — every concept with its metadata (type, status, trust, tags,
  provenance, in/out link degree, description), grouped by top-level dir (`dir`
  on every row carries the full path, `top_dir` the first segment). The "what's
  here, in detail" view. JSON: `{ bundle, count, concepts: [{ id, title, type,
  description, tags, generated_at, generated_by, generated, trust, status,
  stale_after, sources, backlog_ref, dir, top_dir, links_out, links_in }] }`.
  Four of those deserve a sentence: `generated` is the raw boolean ("does the
  document *declare* a generated mapping"), which is what tells hand-written
  apart from v0.1-with-timestamp — `generated_at` alone conflates them, because
  §13.1 lifts a legacy `timestamp` into it. `trust` is the derived §5.3 tier as
  a hyphenated literal (`unverified` | `machine-confirmed` | `human-reviewed`) —
  compare against exactly those. `status` is the *declared* value, `null` when
  absent (the row never fabricates frontmatter; the `--status` filter is what
  applies the §5.4 default). `sources` is a count. Temporal fields render
  ISO 8601 (`stale_after` as `YYYY-MM-DD`). The `timestamp` column is retired —
  `--fields timestamp` is a usage error naming the valid fields.
- **`files`** — the folder tree: each concept's filename + title, grouped by
  directory. The "how it's organised" view. JSON: `{ bundle, count, files: [{ path,
  id, dir, type, title, description }] }`.
- **`tags`** — every tag with the concepts that carry it, ordered by count
  descending. The "what themes dominate" view. JSON: `{ bundle, count, tags: [{ tag,
  count, concepts: [id, …] }] }`. `--by type|dir` regroups the list per concept
  dimension with **within-group** counts (a tag spanning groups appears in each);
  each row also carries the tag's **total** across the narrowed set, printed
  `count/total` when they differ — so a tag's locality reads per row (a plain
  count = wholly local; `2/7` = a cross-cutting spread). The substrate for tag
  curation and for [refine](../../playbooks/refine.md)'s domain-vs-concern read;
  the judgment recipes live in the [maintain playbook](../../playbooks/maintain.md)
  and the [refine playbook](../../playbooks/refine.md). JSON: `{ bundle, count, by,
  groups: [{ <dim>, count, tags: [{ tag, count, total, concepts }] }] }`.
- **`types`** — every type with the concepts that carry it, ordered by count
  descending. The "what kinds of knowledge" view. JSON: `{ bundle, count, types:
  [{ type, count, concepts: [id, …] }] }`.
- **`stats`** — bundle rollups: concept / dir / type / cross-link / distinct-tag
  totals plus per-type and per-dir breakdowns. The "shape at a glance" view. JSON:
  `{ bundle, concepts, dirs, top_dirs, concept_types, cross_links, distinct_tags,
  by_type, by_dir, by_top_dir }` (`top_dirs`/`by_top_dir` are the first-segment
  rollup). `dirs`/`by_dir` cover every directory `okf dirs`
  lists — counts are direct, so a directory holding nothing itself is present at
  `0` rather than missing, and `by_dir.keys` is a complete list of what `--dir`
  can address.

Reach for `stats` first to size a bundle, `catalog`/`files` to enumerate it, `tags`
to find thematic clusters — all without standing up the server.
