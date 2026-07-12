# Changelog

## [1.0.0] - 2026-07-12

Initial release.

- `OKF::Concept` / `OKF::Bundle`: pure in-memory model of an OKF v0.1 bundle,
  buildable straight from data (no disk) with link, citation, and markdown
  round-trip primitives.
- `OKF::Bundle::Validator`: the spec §9 conformance gate (hard errors) with the
  spec's soft guidance reported as warnings — broken cross-links are tolerated,
  as §5.3 requires.
- `OKF::Bundle::Linter`: advisory curation-quality report across reachability,
  backlog, completeness, freshness, provenance, and hygiene, with `--json` as a
  machine substrate.
- `OKF::Bundle::Graph`: the knowledge graph (nodes, edges, type/tag indexes) at
  selectable fidelity.
- On-disk handles: `OKF::Bundle::Folder`, `OKF::Bundle::Reader`,
  `OKF::Bundle::Writer` (atomic, validate-before-publish), and
  `OKF::Concept::File`.
- `OKF::Server::App`: the interactive graph as a mountable Rack app — five views
  (graph, catalog, files, tags, stats) with type/area/tag filtering throughout,
  bodies fetched live from disk — served by a built-in WEBrick runner
  (`okf server`).
- `okf` CLI: `validate`, `lint`, `loose`, and `graph`, plus the read views as
  text — `index`, `catalog`, `files`, `tags`, `types`, `stats` — at full parity
  with the browser: every list view narrows with `--type`/`--area`/`--tag`
  (case-insensitive; the bundle root is area `(root)`, accepted as `root`), and
  `tags --by type|area` regroups the tag index per concept dimension with
  within-group counts — the tag-curation view. `server` boots the graph page;
  `skill` installs the companion skill.
- `okf index`: a read view over the progressive-disclosure layer (spec §6) — one
  entry per directory that holds concepts or carries an `index.md`, root first,
  with its authored index body (frontmatter stripped), a type/tag rollup over the
  concepts that live there, its child directories, and the concept listing. A
  directory with concepts but no `index.md` has its listing synthesized (§6 permits
  it) and is flagged. `--area` (repeatable), `--no-body`, and `--json`; advisory,
  always exit 0. Backed by the pure `OKF::Bundle#directory_index`.
- JSON output is **compact by default** across every emitting verb (the
  token-efficient machine substrate, matching the server); `--pretty` indents it
  for reading and implies `--json`. JSON semantics are identical either way — only
  whitespace differs — so any parser is unaffected.
- JSON property projection on the list views: `index`, `catalog`, and `files`
  take `--fields a,b` (emit only these properties) or `--except a,b` (emit all but
  these), so an agent never pays tokens for fields it will not read. The flags are
  mutually exclusive, imply `--json`, match property names case-insensitively, and
  reject an unknown name (exit 2) listing the valid ones; `okf index --no-body` is
  shorthand for dropping the `body` field.
- Bundled companion agent skill (`okf skill <dest>`): SKILL.md carrying the
  judgment (the CLI surface stays self-describing via `--help`) — including the
  orient-before-you-read protocol and the CLI/judgment boundary — the OKF v0.1
  spec, authoring and CLI references (tag-vocabulary curation, the SPEC-section
  map, the closeout gate), and concept/index/log templates.
- Runs on Ruby >= 2.4 with two runtime dependencies: rack and webrick.
