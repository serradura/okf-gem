---
okf_version: "0.2"
---

# okf structure bundle

The **file-level map of this gem**: what every one of the fifty files under
`lib/` is, grouped by the layer that owns it, and the walk a new verb owes.

It is written to be read *before* opening `lib/`, so an agent about to change
something does not re-derive the layering — and it is **pinned**.
`test/unit/bundle_catalog_test.rb` fails when a file under `lib/` is named by no
concept, or when a concept names a file that is gone. That is the whole reason
this bundle exists rather than a section in a maintainer guide: the Map it
replaces lived where nothing checked it, so a file could arrive, move or leave
and the Map would keep reading plausibly.

# What is deliberately not here

Most of okf's knowledge is in the **repository's own bundle** at
[`.okf/`](https://github.com/serradura/okf-gem/tree/main/.okf) — the format, the
pure model, the seven capabilities, the design constraints, and the CLI's design.
This bundle does not copy a word of it, and a second copy of a catalogue is worse
than none: two tables that can disagree teach a reader to trust neither.

So the split, for now, is by *kind* rather than by subject. **What the code is**
is here, beside the code, where a test can hold it to the tree. **What it means
and why** is the repository's, where the format and the layout decisions live
alongside it. When the repository bundle becomes the ecosystem's, okf's half of
it moves in beside this one.

# Areas

* [Structure](structure/) - Every file under `lib/`, grouped by the layer that owns it: the format layer, the model, the analysers, search, the disk shell, the server, the CLI, the skill.
* [Testing](testing/) - The step-by-step walk a new verb or subcommand owes, ending at the checks that will refuse it.
