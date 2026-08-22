---
type: Playbook
title: Adding a Verb, or a Subcommand
description: The steps a new command owes, in order — the file it lives in, the base class it must not re-implement, the three folders it earns a test in, and the catalogue entry the pin will demand.
tags: [testing, playbook, cli]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/cli/command.rb
---

# Before adding one, check it is not already there

Seventeen commands and eleven subcommands already exist, catalogued in
[cli](/cli.md) and [read-views](/capabilities/read-views.md), and `okf help`
prints the same list. Most of what a new verb would want is a *flag* on an
existing view rather than a view of its own: the shared filters and projections
— `--type/--dir/--tag/--status/--trust` and `--fields/--except` — compose with
every list already.

# The walk

1. **Write the failing test first**, in `test/integration/cli/`, in a file named
   for the verb. Run it. It must fail for the reason you predicted — not because
   a fixture is missing or a regex has a typo, which prove nothing about the
   behaviour. A test written *after* the fix certifies only the code it was read
   off.
2. **One file per verb**, at `lib/okf/cli/<verb>.rb`, registering itself at load.
   A subcommand family stays in its parent's file, but earns its own *test*
   file — `registry set` is a surface a user invokes on its own.
3. **Subclass `CLI::Command` and add nothing it already has.** Refs, the shared
   flags, `filter_entries`, `print_inverted_index`, `no_extras?` — the list is in
   [the-cli](/structure/the-cli.md). Re-implementing one of these is how two
   verbs come to disagree about what `--dir` means.
4. **`#call` is the whole public surface.** Everything else is private, so a
   helper cannot become a verb by accident. Answer `.id`, `.group`,
   `.help_rows`, `.hidden?`.
5. **Add its `require` to the block at the bottom of `cli.rb`**, in the position
   you want it to appear in `okf help` — that order *is* the help order, and a
   test pins the result.
6. **Decide the arity, explicitly.** If it takes one bundle, `no_extras?` must
   make a second an exit-2 usage error. If it takes several, it belongs in the
   `across_bundles/` group with the ones that do.
7. **Prove it in every folder it has** — `by_dir/`, `by_registry/`, and
   `across_bundles/` (which for a single-bundle verb means proving the *refusal*).
   Then exercise the whole surface, not the happy path: every flag once, every
   output format it offers, every exit code it can return, and the combinations
   that actually interact.
8. **Update what describes it.** A new file under `lib/` needs its line in the
   concept in [structure/](/structure/) that owns its layer, and the verb needs
   its cell in [cli](/cli.md)'s group table.
   `test/unit/bundle_catalog_test.rb` fails on either. So does the gem's README,
   which owes a line for every verb; nothing enforces that one.
9. **Run the same test unedited**, then read the uncovered lines:
   `bundle exec rake test:integration`, then diff
   `coverage/integration/.resultset.json` for the files you changed. Three
   shapes hide there by habit, because a unit test walked them first: the
   *second* output format, an *error* branch and the exit code it carries, and
   *malformed-input* robustness.

# Where the logic goes

Not in the verb. The CLI parses argv, prints and exits; the question belongs to
the pure model or to an analyser, so that the server, the TUI and the MCP shell
get the same answer without asking the CLI. If a verb is computing something,
it is probably a method on `Bundle` that has not been written yet.

New I/O goes in the shell, new logic in the core, and
`test/unit/boundary_test.rb` fails the build if a pure file forgets.

# The exit codes are a contract

`0` ok, `1` a failing bundle, `2` a usage error. And the older half of that
contract: **`validate` and `lint` stay separate** — a conformance check may not
live in lint and a curation finding may not fail validate. See
[structure/the-analysers](/structure/the-analysers.md).
