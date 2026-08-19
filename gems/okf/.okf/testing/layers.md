---
type: Component
title: The Test Layers, and How to Read Their Coverage
description: Integration is the critical layer and is organised by the three ways a user names a bundle; coverage is measured on it alone, and read as a map rather than a score.
tags: [testing, coverage, fixtures, integration]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: test/integration/cli/cli_integration_case.rb
---

# Integration first, and organised by identity

`test/integration/cli/` is the only place the gem is exercised the way it is
actually used: real argv, real streams, real exit codes, real files.

**Every command and subcommand gets its own file**, named for it —
`cli_catalog_test.rb`, `cli_registry_set_test.rb`. Not one file per topic and not
one per verb family: `registry list`/`set`/`del`/`default`/`rename` are five
files, because each is a surface a user invokes on its own.

**The folders are the three ways a user names a bundle**, and a command is
proven in each one it has:

```
test/integration/cli/
  cli_integration_case.rb   the shared base: okf(), with_registry(), okf_server()
  fixtures/                 bundles used by more than one group
  by_dir/                   `okf lint ./docs`      — named by path
  by_registry/              `okf lint @handbook`   — named through the registry
  across_bundles/           `okf search @a @b`     — several at once
  cli_help_test.rb …        the commands that name no bundle
  cli_plugin_test.rb        the extension seam — a plugin on the load path
```

Same command, same flags, three identities — because identity is where the CLI
decides what to answer about, and a verb that works by path can still be broken
by ref. Classes are namespaced per folder (`ByDir`, `ByRegistry`,
`AcrossBundles`) so three files can share a name.

`across_bundles/` covers **every** bundle-taking verb, not only the two that
merge: for the eleven with no multi-bundle form, the test proves a second bundle
is *rejected* with exit 2. That boundary was a real silent-wrong-answer bug —
`okf lint a b` once linted `a`, ignored `b`, and exited 0.

# The other layers, and what only they can reach

| suite | what only it proves |
|---|---|
| `test/unit/boundary_test.rb` | the core/shell split — a pure file naming a shell class, or touching `File`/`Dir`/`FileUtils`/stdio |
| `test/unit/loading_test.rb` | `require "okf"` pulls in neither the CLI nor the skill, in a clean subprocess |
| `test/unit/packaging_test.rb` | what ships: real files, never symlinks, byte-identical to the root's |
| `test/plugin/sync_test.rb` | the generated skill copies, by file list and checksum |
| `test/browser/` | that the page *works* — see [the-graph-page](the-graph-page.md) |

# Read coverage as a map, not a score

```bash
bundle exec rake test:integration   # integration only + coverage/integration/
```

The full suite's number is flattering: unit tests call classes directly and reach
code no user can. So coverage is measured on integration alone, and read by
where it is low.

* Low in `bundle/writer.rb` or `concept/file.rb` is **expected** — no verb writes
  a bundle, so those are the library API's to prove.
* Low in `cli/`, `registry.rb` or `server/` is a **hole**: a path a user can
  reach that no user-shaped test walks.

**Prove completeness by reading the uncovered lines, not by judgment.** After a
feature, diff `coverage/integration/.resultset.json` for the uncovered lines in
the files you changed. Three shapes hide there by habit, because a unit test
walked them first: the *second* output format (the human listing when only
`--json` was asserted, or the reverse), an *error* branch and the exit code it
carries, and *malformed-input* robustness (a hand-edited registry — a cycle, an
unnormalised slug, a missing field). The registry groups shipped with nine
integration tests that read as exhaustive and left six such branches, a whole
human-rendering path among them.

# Do not skimp on fixtures

They are the substrate the layer stands on; a committed bundle is cheaper than a
mock and far more honest, and reviewers can read it. **Fixtures follow common
closure** — one used by a single group lives under that group, one used by
several lives in the shared `fixtures/`.

When a path is unreachable from the existing fixtures, **add the fixture**. Never
bend a test toward what the fixtures happen to make easy. `rooted` exists because
`tags --by area`'s `(root)` label was unreachable from all twelve fixtures that
preceded it — and a branch no fixture can reach is a branch nobody has ever
proven.
