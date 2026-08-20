# Structure

Every file under `lib/`, grouped by the layer that owns it. One concept owns
each file, and `test/unit/bundle_catalog_test.rb` fails if that stops being true
in either direction — a file no concept names, or a concept naming a file that
is gone.

Read it as a pipeline. An event arrives at a door, the world is read into data,
a gate or a guard asks one question of that data, and — only for the write
verbs — a transform is planned, conserved and committed.

* [doors](doors.md) - `lib/okf/pro.rb`, `lib/okf/plugin.rb`, `lib/okf/pro/cli.rb`, `lib/okf/pro/version.rb` — the seam, the contract's constants, and the one dispatcher.
* [reading-the-world](reading-the-world.md) - `bundle_root.rb`, `event.rb`, `target.rb`, `board.rb`, `log.rb`, `records.rb` — where the bundle is, what arrived, and the two documents as data.
* [the-gates](the-gates.md) - `reconcile.rb`, `budget.rb`, `closing.rb`, `snapshot.rb`, `attestation.rb`, `pairing.rb`, `conformance.rb`, `state.rb`, `audit.rb` — one question each, and the two doors that ask them all.
* [the-guards](the-guards.md) - `guards.rb`, `shell_guard.rb` — the trust rules, and the same rules at the door a shell command comes through.
* [the-writers](the-writers.md) - `conserve.rb`, `board/edit.rb`, `log/edit.rb`, `writes.rb` — pure transforms, a declared delta, and the refusal that enforces it.
* [the-scaffold](the-scaffold.md) - `scaffold.rb` and the template tree it writes.
* [the-recorder](the-recorder.md) - `friction.rb` — telemetry about the tooling, which refuses nothing and blocks nothing.
