# Capabilities

The seven things the gem does over a bundle, plus the read views that print it at
a glance. All of them run over the same [pure model](../model/) and are fronted
by the [CLI](../cli.md).

# Judge

* [Conformance validator](validator.md) - the §9 legal check; the only capability that can fail a bundle.
* [Curation linter](linter.md) - advisory quality report across six categories; never rejects.

# Serve & read

* [Interactive graph server](graph-server.md) - a self-contained HTML graph over HTTP — one bundle or many behind a hub — mountable as a Rack app.
* [Workspace manager](workspace-manager.md) - the hub's `/b/` page: every bundle with its size, health and default marker, and the forms that manage the registry from a browser.
* [Static render](render.md) - the same page written to one self-contained static file, the bundle baked in, to host where there is no server (`okf render`).
* [Read views](read-views.md) - `index`, `catalog`, `files`, `types`, `tags`, `stats`, `loose`, `graph` — the browser views as text, plus the `index` map.
* [Ranked text search](search.md) - deterministic ranked retrieval over metadata and bodies; answers "which concept covers X?" in a few rows.

# Use & author

* [Library API](library-api.md) - the Ruby surface: pure model plus on-disk handles.
* [Companion agent skill](agent-skill.md) - the skill shipped inside the gem that teaches an agent to author OKF.
