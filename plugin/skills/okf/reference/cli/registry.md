# `registry` — naming bundles once

Kind: reference. Answers: which file a registry op writes and how okf finds it,
which verbs key on a path and which on a slug, what a group is and which two
verbs consume one, and why the default is a position rather than a stored slug.

The *persistent registry* is a plain JSON file under `$OKF_HOME` (default
`~/.okf`), managed by the `okf registry` umbrella — like git's `remote` family,
and split by what each verb keys on. It is what every `@slug` resolves through
([cli.md](../cli.md)) and what a bundle-less `okf server` hosts
([serve.md](serve.md)).

**`okf registry init`** creates a *project-local* registry instead: a
`.okf-registry.json` in the current directory, which okf discovers by walking up
from the working directory and uses in place of the global one while you are
inside its tree (the nearest wins, so nested registries resolve nearest-first).
Every registry op — and every `@slug` — then resolves through it, so a bare
`okf server` inside a repo serves that repo's bundles with no `$OKF_HOME` setup;
`okf registry list` names the local file it found. `OKF_NO_DISCOVERY=1` forces
the global registry — the escape hatch for a fixed-cwd caller (CI, a tool). A
local registry stores **portable** paths: a bundle inside its tree is written
relative to the `.okf-registry.json`, so committing the file lets it travel with
the repo (a checkout elsewhere, a container mounting it) and resolve unchanged;
a bundle outside the tree stays absolute, since it cannot travel. Paths still read
back absolute wherever the CLI reports them.
**Entry verbs** take a path: `okf registry set <dir>` adds it
(slug from the basename, or `--as`, which errors on a collision; `--default`
puts it first), and because the entry is keyed by path, `set` on an
already-registered dir updates it in place — refreshing its title, and renaming
it when `--as` is given. `okf registry del <dir|@slug>` removes a bundle *or* a group — by name, so an
entry whose directory is already gone still deletes, and removing a bundle
**cascade-drops** it from every group that named it (a group emptied that way is
deleted). Slug *or* dir, never both readings at
once: an argument with a `/` in it names a location and only a location, so
`del ./notes` refuses when no entry points there rather than stripping to the
slug `notes` and deleting a bundle somewhere else entirely.
<!-- rule:okf-registry-del-path-or-slug -->
**Slug verbs** take the name — bare, or as an `@slug`: `okf registry default <@slug>`
chooses which bundle `/` opens **by moving that entry to the front** (a group is
refused — the default is one bundle), and
`okf registry rename <@slug> <new>` renames a bundle *or* group slug (mount path
and switcher name), **cascading** the new name into every group's member list —
`<new>` is a name being minted, so it is never a ref. The registry is ordered and **the first entry still on disk is the
default** — that is the whole rule, so the first bundle you register is the
default until you move another one, a rename keeps its position, and a `del`
promotes whatever is next. A vanished directory is stepped over (the server
cannot open one, so starring it would name a bundle `/` never serves), and
`registry default @slug` refuses one outright — the same refusal `registry set`
gives a directory that is not there. The file is hand-editable and reorders
visibly, which is the point: there is no stored slug that can dangle.
<!-- rule:okf-registry-default-position -->
**Group verbs** name a *set* of bundles under one slug — a durable subset for the
two verbs that take several bundles. `okf registry group <slug> <@member…>`
creates a group, or adds members to one (a union); members are bundle *or* group
slugs, so groups nest. A group shares the slug namespace with bundles (a slug
names one *or* the other, never both), `all` stays reserved, and a member set that
would make the group reach itself is refused. `okf registry ungroup <slug>
<@member…>` removes members; emptying a group deletes it. A group resolves,
recursively and path-deduped, to its bundle leaves — which **only `okf search`
and `okf server` consume**: every single-bundle verb (`lint`, `index`, …) refuses
a `@group` with exit 2, the same rule that refuses a second bundle. `@all` is
unchanged — it still names every registered *bundle*, groups being named subsets
of that.
`okf registry list` (or a bare
`okf registry`) stars the default and flags vanished dirs `(missing)` — the
server skips those with a note — and lists any groups with their members and
resolved leaf count; `--json` answers
`{ registry: <file>, count, bundles: [{ slug, title, dir, mount, default,
missing }], groups: [{ slug, members, resolved }] }`, naming the file it read so a
`$OKF_HOME` mismatch is visible.
