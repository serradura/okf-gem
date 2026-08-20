# Interaction

The keyboard model, and the UX decisions that were arrived at by getting them
wrong first.

* [Key Routing and Its Modes](key-routing.md) - The dispatch order, why `/` starts every text field, and the `case`-guard trap for letters that mean two things.
* [Esc Peels One Layer](esc-peels-one-layer.md) - Esc ends the innermost thing only — the rule that stops a find from costing you the file you were reading.
* [Search Submits, It Does Not Follow Typing](deferred-search.md) - Why Enter runs the search, and the regression that renders identically to the correct behaviour.
* [Which Registry a Session Is On](which-registry.md) - okf resolves a project-local registry before the global one; being the single verb that disagreed was a silent wrong answer rather than an error.
* [Active Bundle and Scope Are Two Axes](cross-bundle-scope.md) - Reading one bundle while searching many, and why reconciliation keys on the directory.
* [A Dead Filter Offers the Wider Search](filter-escalates-to-search.md) - Filter reads metadata in one bundle, search reads bodies across all of them.
* [Following a Link Out of the Page](following-links.md) - A picker rather than inline hints, the directory link okf declines to resolve, and the count it deliberately disagrees with.
