# `registry` — naming bundles once

Kind: reference. Answers: which file a registry op writes and how okf finds it,
which verbs key on a path and which on a slug, what a group is and which two
verbs consume one, why the default is a position rather than a stored slug, and
what a link brings in from another registry file — against what an import copies
out of one.

The *persistent registry* is a plain JSON file under `$OKF_HOME` (default
`~/.okf`), managed by the `okf registry` umbrella — like git's `remote` family,
and split by what each verb keys on. It is what every `@slug` resolves through
([cli.md](../cli.md)) and what a bundle-less `okf server` hosts
([serve.md](serve.md)).

**`okf registry init`** creates a *project-local* registry instead: a
`.okf.json` in the current directory, which okf discovers by walking up
from the working directory and uses in place of the global one while you are
inside its tree (the nearest wins, so nested registries resolve nearest-first).
Every registry op — and every `@slug` — then resolves through it, so a bare
`okf server` inside a repo serves that repo's bundles with no `$OKF_HOME` setup;
`okf registry list` names the local file it found. `OKF_NO_DISCOVERY=1` forces
the global registry — the escape hatch for a fixed-cwd caller (CI, a tool) — and
**`-g`/`--global` says the same thing for one command**, on every subcommand but
`init` (whose whole job is to create a local file). So `okf registry list -g`
reads the global registry from inside a repo, and `okf registry set <dir> -g`
registers there without leaving. `list` names the file it read whenever either
lever is in play, so which registry answered is never a guess. A
local registry stores **portable** paths: a bundle inside its tree is written
relative to the `.okf.json`, so committing the file lets it travel with
the repo (a checkout elsewhere, a container mounting it) and resolve unchanged;
a bundle outside the tree stays absolute, since it cannot travel. Paths still read
back absolute wherever the CLI reports them.
The file okf writes is `.okf.json`; the older `.okf-registry.json` is still
discovered, both names checked in each directory on the way up so "nearest wins"
keeps its shape, and `okf registry` — that verb alone, never `lint` or `search` —
notes the old name once so it can be retired with a `git mv`.

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
**Link verbs** point the *global* registry at another registry file, so its
bundles resolve here without being copied. `okf registry link <name> <file>`
adds the pointer (the target must exist); its bundles then answer to their own
slugs, or to `<name>-<slug>` when a name is already taken here, and `@<name>`
resolves as a group over them. Nothing is written but the pointer — the target
keeps owning its rows, so an edit there shows here on the next read, and every
write aimed at a linked bundle (`rename`, `del`, `default`, `set --as`, `group`)
is refused naming the file that does own it. `okf registry unlink <name>` drops
the pointer and its bundles. Links are the **global** registry's alone: a
project-local one parses them and does not resolve them, which is why a linked
file's own links are never followed and there is no chain to cycle. A target
that is gone or unparseable is listed `(missing)`/`(unreadable)` and resolves to
nothing — one dead pointer never takes down the registry holding it.
<!-- rule:okf-registry-links-global-only -->
**`okf registry import <@slug…>`** is the opposite trade: it *copies* chosen rows
out of another registry file into the one in force, and they become yours —
editable, renameable, groupable, and untouched when the source changes. The
source is `--from FILE`, defaulting to the global registry, because `-g` goes on
meaning the registry written *to*. A group ask brings its members, and any group
nested inside it, recreated under the same names. Slugs are preserved, so a
collision **refuses** rather than being minted around the way a link's is — you
typed this name, and the gem may not substitute one you chose (`--as` renames a
single ask). A bundle already registered here under another name refuses first.
Every ask is checked before anything is written, so an import either lands whole
or leaves the file byte-for-byte alone.
<!-- rule:okf-registry-import-all-or-nothing -->
`okf registry list` (or a bare
`okf registry`) stars the default and flags vanished dirs `(missing)` — the
server skips those with a note — and lists any groups with their members and
resolved leaf count; `--json` answers
`{ registry: <file>, count, bundles: [{ slug, title, dir, mount, default,
missing, link, origin }], groups: [{ slug, members, resolved, link }], links:
[{ slug, registry, bundles, missing, unreadable }] }`, naming the file it read so a
`$OKF_HOME` mismatch is visible. On a bundle row `link` names the link it arrived
through (null when the registry owns it) and `origin` the slug it carries in that
file — the two differ only where a collision moved the name. `groups` lists both
kinds, own first, each carrying the same `link` key, since a linked group
resolves as a ref like any other.
