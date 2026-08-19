---
type: Component
title: The CLI — a Registry, a Base Class, and One File per Verb
description: The only layer that parses argv, prints and exits; a verb is a class answering four questions about itself and one about a run, and the require order at the bottom of `cli.rb` is the order `okf help` prints.
tags: [structure, cli, shell, extension-point, plugins]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/cli.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/cli.rb` | the command registry, the dispatcher, plugin discovery, and `okf help` |
| `lib/okf/cli/command.rb` | the base every verb inherits: streams, refs, shared flags, printers |

And one file per verb, each registering itself at load:

| verb file | verb |
|---|---|
| `lib/okf/cli/skill.rb` | `skill` |
| `lib/okf/cli/server.rb` | `server` |
| `lib/okf/cli/render.rb` | `render` |
| `lib/okf/cli/registry.rb` | `registry` and its eight subcommands |
| `lib/okf/cli/lint.rb` | `lint` |
| `lib/okf/cli/loose.rb` | `loose` |
| `lib/okf/cli/validate.rb` | `validate` |
| `lib/okf/cli/search.rb` | `search` |
| `lib/okf/cli/index.rb` | `index` |
| `lib/okf/cli/dirs.rb` | `dirs` |
| `lib/okf/cli/stats.rb` | `stats` |
| `lib/okf/cli/types.rb` | `types` |
| `lib/okf/cli/tags.rb` | `tags` |
| `lib/okf/cli/files.rb` | `files` |
| `lib/okf/cli/references.rb` | `references` |
| `lib/okf/cli/catalog.rb` | `catalog` |
| `lib/okf/cli/graph.rb` | `graph` |

**That table's order is the require order at the bottom of `cli.rb`, and the
require order IS the order `okf help` lists the verbs in.** A test pins the
result, but the coupling is in the source. What each verb answers is
[capabilities/verbs](/capabilities/verbs.md).

# What a verb is

A `CLI::Command` subclass answering four questions about itself — `.id`,
`.group`, `.help_rows`, `.hidden?` — and one about a run: `#call(argv)`,
returning the exit status. **Privacy is the boundary**: `#call` is the whole
public surface, so a helper cannot become a verb by accident. `DUCK_TYPE` is
that contract, checked at registration.

`GROUPS` is the ordering of the sections `okf help` prints; `ROW_FIELDS` is the
`--fields`/`--except` projection vocabulary.

# What the base class already gives you

Do not re-implement any of these in a verb:

* **refs** — `all_ref?`, and the `@slug` / bare `@` / `@group` resolution every
  verb inherits, so `okf lint @handbook` works without the verb knowing about
  registries.
* **flags** — `json_flags`, `help_flag`, `projection_flags`, `filter_flags`,
  `depth_flag`. `FILTER_KEYS` is the shared filter vocabulary.
* **filtering** — `filter_entries`, `dir_scope`, `under_dir?`, and the `--area`
  deprecation shim in `fold_area`.
* **printing** — `print_inverted_index` is the shared shape behind `types`,
  `tags` and friends.
* **arity** — `no_extras?` is what makes a second bundle an exit-2 usage error
  for the verbs that take only one. That was a real silent-wrong-answer bug:
  `okf lint a b` once linted `a`, ignored `b`, and exited 0.

# `CLI.register` is the extension point

Append-only, idempotent by id, duck-type checked — **deliberately the same shape
as `Search.register`**. Any gem with `okf/plugin.rb` on its load path can
register a verb and okf finds it, with no edit here and no list of known addons
(a test greps `cli.rb` to keep it that way).

Discovery is **lazy**: a built-in never triggers a scan, so only an unknown verb
or `okf help` pays for it. A plugin that raises is skipped and reported on
stderr, never fatal. `declined` and `register_declined` are how a collision is
reported rather than silently won.

`PLUGIN_GEM_PREFIX` is `okf-`: **only gems named `okf-*` are loaded**, the same
convention Jekyll and Vagrant use. Argue it as a convention if it is revisited —
the threat it closes is thin, and overselling it invites false confidence.

One rule underneath it *is* load-bearing: **naming a gem must never load it.**
`plugin_gem_name` reads the spec's `full_gem_path` and requires nothing, because
a refusal that happens after the `require` is not a refusal; a test pins it. A
path belonging to no gem stays trusted — `ruby -I`, a Gemfile `path:`, a
checkout — someone put it there.

`seal_builtins!` is the line between what ships and what was installed, and it
is what `extension?` reads to print the "installed extensions" section.
