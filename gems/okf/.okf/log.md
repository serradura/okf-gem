# Update Log

## 2026-08-19

* **This bundle begins, as the gem's file-level map — and only that.** The
  repository-root `AGENTS.md` carried a hand-maintained Map of `lib/**` and
  nothing checked it: a file could arrive, move or leave and the Map would keep
  reading plausibly. [Structure](/structure/) now owns it, eight concepts over
  the fifty files, and `test/unit/bundle_catalog_test.rb` fails on a file no
  concept names or a concept naming a file that is gone.

  It deliberately copies nothing from the repository's own bundle, which is
  still okf's: the format, the pure model, the seven capabilities and the design
  constraints stay there. A second copy of a catalogue is worse than none, since
  two tables that can disagree teach a reader to trust neither. So the split is
  by *kind* — what the code **is** lives beside the code where a test can hold
  it to the tree; what it **means** stays where the format and the layout
  decisions are.

  The one catalogue that already existed — the group table in the repository
  bundle's `cli.md` — was code-derived and unchecked. The same test now pins it
  against `OKF::CLI.builtins`, in place rather than by copying it here.
