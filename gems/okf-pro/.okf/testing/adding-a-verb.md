---
type: Playbook
title: Adding a verb, or a check
description: The nine steps a new `okf pro` surface owes, in order — where the logic goes, which table it joins, which test file it earns, and which catalogue entry the pin will demand.
---

# Decide the family first

Four families, and they differ in how they are dispatched, what they may accept
and what they may do. [capabilities/verbs](/capabilities/verbs.md) has the table.

* a **check** rides a hook event, reads stdin, and answers in the protocol's
  exit codes — 0 or 2, never 1;
* a **reader** answers a question about a bundle and takes flags;
* a **writer** changes a file, and is refused by `Conserve` unless its declared
  delta is exactly what happened;
* a **scaffold** verb takes a destination, not a bundle.

Getting this wrong is not stylistic. A reader that skips `parse_flags` reports
its caller's typo as a broken bundle; a check that returns 1 is read as
*proceed*.

# The walk

1. **Write the failing test first**, in `test/integration/`, in a file named for
   the verb — `cli_<verb>_test.rb`, one file per verb and subcommand. Run it.
   It must fail for the reason you predicted, not because a fixture is missing.
2. **Put the logic in a module, not in the CLI.** `cli.rb` dispatches, parses
   flags and prints; the question itself belongs in the module that owns that
   part of the world. [structure/](/structure/) says which one, and a genuinely
   new layer earns a new file *and* a line in the concept that owns it.
3. **Join the right table** in `cli.rb`: `CHECKS` (which puts it in
   `HOOK_NAMES` automatically), or `READERS`, `WRITERS`, `SCAFFOLD`.
4. **Add its `USAGE` row**, and the matching row in `OKF::CLI::Pro.help_rows`.
   The two are separate literals on purpose — reading `USAGE` from the plugin
   would make every `okf help` load the whole library — and they are held
   together by a test rather than by discipline.
5. **Declare its flags** in `FLAGS` if it takes any. Absence means "accepts
   none", not "is exempt": every reader routes through `parse_flags` either way.
6. **A writer owes a pure transform.** Compute the new text in `board/edit.rb`
   or `log/edit.rb` — they cannot touch the disk — declare the added, removed
   and moved lines, and let `Conserve` refuse the mismatch. See
   [the-writers](/structure/the-writers.md).
7. **A check owes a drill** in `test/integration/wrapper_test.rb` if it adds a
   way for enforcement to be absent. Half the drills there assert a *pass*, and
   yours should too: a wrapper that refused everything would satisfy every
   refusal drill in the file. See [drills-over-units](drills-over-units.md).
8. **Update the catalogue** — [capabilities/verbs](/capabilities/verbs.md) or
   [capabilities/checks](/capabilities/checks.md). This is not documentation
   etiquette: `test/unit/bundle_catalog_test.rb` compares those tables against
   `CLI::USAGE` and `CLI::HOOK_NAMES`, so the suite is red until you do.
9. **Run the same test unedited.** If it needed editing to pass, it was written
   after the code and certifies only what the code happens to do.

# What the fixture will do to you

`BundleFixture` is a **client of the code under test** — `write_log` computes
its snapshot line by calling `Snapshot.line` — so "the suite is green, therefore
nothing changed" holds only for changes that do not touch what the fixture
calls. [fixture-is-a-client](fixture-is-a-client.md) is the full argument.
