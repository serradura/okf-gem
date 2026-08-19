# Contract

The three clauses, and what each costs when it is broken.

* [the-contract](the-contract.md) - Blocking checks fail closed, feedback checks fail loud, no check fails silent.
* [exit-codes](exit-codes.md) - Why `hook` reads only 0 and 2, and why `audit` never spells a crash as 1.
* [gates-only-at-the-hook-door](gates-only-at-the-hook-door.md) - A CI verb accepted as a check name reports clean without reading the event.
* [containment-directions](containment-directions.md) - An escaping path is refused, ignored, or read as open — one decision per call site.
* [telemetry-does-not-lie](telemetry-does-not-lie.md) - The third clause applied to the friction recorder, which is not a check and still may not report an uncounted zero.
* [silent-skips](silent-skips.md) - The third clause broken by the checker itself, on its own gate path.
