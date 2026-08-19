---
type: Component
title: The Disk Shell
description: Where a directory becomes a Bundle and back — the reader, the atomic writer that validates before it publishes, the folder handle everything above it uses, and the registry.
tags: [structure, shell, io, registry, atomic]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/bundle/folder.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/concept/file.rb` | one concept as an on-disk handle: read, save, delete, reload |
| `lib/okf/bundle/reader.rb` | a directory to a `Bundle`, unparseable files kept rather than dropped |
| `lib/okf/bundle/writer.rb` | a `Bundle` to a directory — locked, validated, then promoted atomically |
| `lib/okf/bundle/folder.rb` | the on-disk bundle handle every layer above actually holds |
| `lib/okf/registry.rb` | which bundles a machine or a project knows, addressed as `@slug` |

These are the shell. Everything they call into is pure, and
`test/unit/boundary_test.rb` keeps the arrow pointing one way.

# Folder is the handle, not a convenience

`Folder.load(dir)` is what the CLI, the server, the TUI and the MCP shell all
hold. It delegates `validate`, `lint`, `graph`, `skeleton`, `catalog`, `hubs`,
`directories`, `directory_index`, `stats`, `tag_groups`, `references` and
`log_entries` to the pure model, and adds only what needs the disk:
`concept_source`, `reference_files`, `reload`, `save`, and `Folder.label`.

Reach for `Folder`, not `Reader` — the reader is how a folder is built, once.

# The writer publishes or it does not

`Writer#call` takes a lock, writes the whole tree to a temporary path, runs the
**validator** against it, and only then promotes it into place. A bundle that
would not validate is never published, and a crash mid-write leaves the old tree
intact. `AlreadyExistsError` and `ValidationErrorFromResult` are the two
refusals; `safe_markdown_path!` is the containment check, borrowed from the
format layer rather than rewritten.

No CLI verb writes a bundle. This is the library API's surface, which is why its
integration coverage is low *by design* — see [the-suite](/testing/layers.md).

# Registry: two files, one answer

`Registry` is the `@slug` layer. `HOME_ENV`/`DEFAULT_HOME` is the global
registry under `$OKF_HOME` (default `~/.okf`); `LOCAL_FILE` is the project-local
`.okf-registry.json` that `discover` finds by walking up from the working
directory. **A discovered local registry replaces the global one outright** — it
does not merge — and `NO_DISCOVERY_ENV` (`OKF_NO_DISCOVERY=1`) is the escape
hatch that forces the global one, which is what a test that must not see the
developer's registry sets.

`relative_base` is why a local registry's paths stay relative and the file
travels with the repository. `Registry#reopen` preserves it; `Registry.new(path)`
does not, and reaching for the latter is how a reload comes to resolve every
bundle against the wrong base.

`Group` is a named, recursive set of bundles. `RESERVED_SLUGS` is `all`, because
`@all` means every bundle and may not be shadowed. `slugify`, `dedupe`,
`normalize` and `path_shaped?` are the naming rules a `registry set` goes
through.
