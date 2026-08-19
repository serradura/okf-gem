# Update Log

## 2026-08-19

* **This bundle begins, as the gem's structural documentation.** The
  repository-root `AGENTS.md` carried a hand-maintained Map of `lib/**` and a
  full account of the test layers, and nothing checked either: a file could
  arrive, move or leave and the Map would keep reading plausibly.
  [Structure](/structure/) now owns the Map — eight concepts over the fifty
  files — [Capabilities](/capabilities/) owns the catalogue of the seventeen
  verbs, the eight `registry` subcommands and the library surface, and
  [Testing](/testing/) owns the layers, the coverage reading and the browser
  obligation. `test/unit/bundle_catalog_test.rb` is the pin, and it bites in
  both directions: a file no concept names, a concept naming a file that is
  gone, or a verb catalogue that disagrees with `OKF::CLI.builtins`.

  The repository bundle keeps the **format** — what a citation is, what §5
  declares — because the skill, the plugin and every non-Ruby implementation
  speak it, and a reader asking about §5.1 is not asking about this gem.
