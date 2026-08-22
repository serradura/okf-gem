# Update Log

## 2026-08-21

* **The freshness stamp watches every file the registry reads** —
  [the tool set](design/the-tool-set.md). okf's registry can now `link` another
  registry file, and that file's bundles resolve into the served set; the stamp
  still stat'd this server's own file alone, so an `okf registry set` over there
  moved nothing it watched and a long-running server kept answering about the
  set it booted with. That is the silent wrong answer the stamp exists to
  prevent, arriving through a second door. The two kinds of file keep **different
  rules**: this server's own registry going unreadable holds the last good set,
  because a file caught mid-write must not empty what is being served, while a
  linked target that vanishes drops its bundles — okf already reports a missing
  one as resolving to nothing, and following that beats freezing it. Riding out
  an error and following a state change are different jobs, and one stamp had to
  do both.

* **`list_bundles` names the linked groups too.** They were resolvable as a
  `bundle` argument and absent from the listing, because okf split them into a
  second method — an agent could open `@brain` and never learn it existed. The
  kernel folded them back into `groups_listing`, so this needed no change here
  beyond the `link` key now on each row.

## 2026-08-19
* **Addition**: **okf-mcp has a knowledge bundle, and `AGENTS.md` now relies on
  it** — [structure](structure/), [capabilities](capabilities/),
  [design](design/), [testing](testing/). The structural layer moved rather
  than being copied: the file-by-file Map, the hard constraints and the testing
  doctrine were `AGENTS.md`'s, and `AGENTS.md` now carries the contract, the
  commands and a pointer here. A fact stated twice is a fact that drifts.
* **Addition**: **the catalog is pinned, not trusted** —
  [what each test layer proves](testing/layers.md). Structural documentation is
  derived from code, so `test/unit/bundle_catalog_test.rb` fails when a `.rb`
  under `lib/` is named by no concept, when a concept names a file that is gone,
  or when the tool catalog and `server.rb` disagree. The Map it replaces lived
  in `AGENTS.md` where nothing checked it, which is the failure this closes.
