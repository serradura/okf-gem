# Update Log

## 2026-07-12
* **Sync**: caught the bundle up with the gem at 1.1.0 — the [graph server](capabilities/graph-server.md) now sanitizes each fetched body with DOMPurify before rendering, so the [server trust boundary](design/server-trust-boundary.md) closes the on-demand render path (its [design listing](design/) reworded to match), and the [library API](capabilities/library-api.md) notes that `require "okf"` loads the library alone now that the CLI and skill load on demand.
* **Sync**: caught the bundle up with the CLI at 1.0.0 — documented the new `index` command (the §6 progressive-disclosure map, the read view that sees the reserved `index.md` layer), compact-by-default JSON with `--pretty`, and `--fields`/`--except` projection on the list views, in [read views](capabilities/read-views.md) plus the `index`-verb enumerations in the [CLI](cli.md), the [overview](overview.md), and the [capabilities](capabilities/) index listing.

## 2026-07-11
* **Creation**: seeded the bundle documenting okf-gem's capabilities at version 0.1.0 — the [overview](overview.md), the [CLI](cli.md), and the [format](format/), [model](model/), [capabilities](capabilities/), and [design](design/) areas.
* **Update**: added Mermaid diagrams (tagged `diagram`) to five concepts — [overview](overview.md), the [core/shell split](design/core-shell-split.md), the [graph server](capabilities/graph-server.md), the [library API](capabilities/library-api.md), and [cross-links](format/cross-links.md).
* **Sync**: caught the bundle up with the CLI — documented the new `types` command, the cross-view `--type`/`--area`/`--tag` filters, and `tags --by type|area` in [read views](capabilities/read-views.md), the [CLI](cli.md) front end, the [graph](model/graph.md) indexes, and the [capabilities](capabilities/) index listing.
