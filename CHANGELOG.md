# Changelog

## [Unreleased]

- `okf types`: the type index as a CLI view — every type with its concepts,
  ordered by count, `--json` for the machine shape (parity with the server's
  `/types` endpoint).
- The CLI list views narrow with the same filters the browser offers:
  `--type` / `--area` / `--tag` on `catalog` and `files`, `--type` / `--area` on
  `tags`, `--area` / `--tag` on `types`. Case-insensitive; a filter that matches
  nothing is an empty view, not an error.
- Concepts at the bundle root now report area `(root)` (previously their own id),
  so `stats --json` `by_area` and the catalog grouping match the server UI;
  `--area root` selects them.
- Server UI: the Tags view gains type/area filters, the Files view a tag
  combobox, the Catalog filters grow Areas and Tags groups, and both the graph
  and catalog filter panels get a find box that narrows the filter chips
  themselves (searching reaches all tags, not just the top 40).

## [0.1.0] - 2026-07-11

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
  (graph, catalog, files, tags, stats), bodies fetched live from disk — served
  by a built-in WEBrick runner (`okf server`).
- `okf` CLI: `validate`, `lint`, `loose`, `graph`, `catalog`, `files`, `tags`,
  `stats`, `server`, and `skill`.
- Bundled companion agent skill (`okf skill <dest>`): SKILL.md, the OKF v0.1
  spec, authoring and CLI references, and concept/index/log templates.
- Runs on Ruby >= 2.4 with two runtime dependencies: rack and webrick.
