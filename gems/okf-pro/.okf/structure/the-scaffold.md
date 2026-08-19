---
type: Component
title: The scaffold — what `setup` writes, and who owns it afterwards
description: "One generator, two template trees, and a split by ownership rather than by subject: `upgrade` rewrites the gem's files and never touches a seeded one."
---

# The file

| file | what it owns |
|---|---|
| `lib/okf/pro/scaffold.rb` | `setup`, `upgrade`, `skill` — the generator and its refusals |

Plus `lib/okf/pro/template/`, which is not code: it is the tree `setup` writes.
It ships, and the gemspec says why — a gem without it installs a verb that
cannot do its job.

# Two trees, and the split is ownership

`GEM_DIR` (`template/gem/`) holds the machinery: `upgrade` rewrites those files
in place, every time, without asking. `SEED_DIR` (`template/seed/`) holds the
adopter's: written once by `setup`, never touched again.

Reclassifying `CLAUDE.md`, `.gitignore` or `settings.json` as machinery would
make `upgrade` destroy exactly the hand-merge `setup` told the adopter to
perform. The argument is [ownership-not-subject](/scaffold/ownership-not-subject.md).

`DOTFILES` maps `gitignore` to `.gitignore` — stored without the dot, because a
dotfile inside the template is a file `git ls-files` and every glob treat
differently. `EXECUTABLE` is the two files that must land with the bit set.
`SUFFIX` (`.okf-pro-new`) is what a collision is written as instead of an
overwrite; `flat_layout_refusal` is what happens when the destination is not a
shape this gem can complete.

# What must not appear

No date ships in the generated bundle, outside a code span — and the exemption
*is* required rather than cosmetic, because the closure marker has to be taught
and `Pairing::MARKER` requires a date. Both directions of that coupling are
pinned by `test/unit/closure_grammar_test.rb`. See [no-date-ships](/scaffold/no-date-ships.md).
