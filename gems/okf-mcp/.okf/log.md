# Update Log

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
