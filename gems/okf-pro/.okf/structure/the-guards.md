---
type: Component
title: The guards — the trust rules, and the same rules at the shell door
description: Two files asking the same questions at two doors, because a `cat > concept.md` is seen by neither the Edit tool nor the file-path checks.
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The files

| file | the door |
|---|---|
| `lib/okf/pro/guards.rb` | an `Edit` or `Write` tool event: the trust rules on the text about to land |
| `lib/okf/pro/shell_guard.rb` | a `Bash` tool event: the same rules, read out of a command line |

# What they ask

`Guards.attests?` is the trust question — does this text set `verified:`?
`ATTESTATION` matches the block form, `FLOW_ATTESTATION` the inline-mapping
form, and both exist because a rule that only knew one spelling waved the other
through. `guard_verified` is the gate that uses them; `journal_guard` is the
append-only rule for `journal/YYYY-MM-DD.md`, which `JOURNAL_ENTRY` recognises.

`ShellGuard.check` reads the same rules out of a command. `MUTATORS` is the
list of commands that can write, `SEPARATORS` splits a compound command so a
mutator after `&&` is not missed, `MARKDOWN` finds the paths, and `own_write?`
is what keeps `okf pro` verbs from being refused by the guard that exists to
make people use them.

# Why there are two

A gate reads a tool event. A shell redirect is not one — a `cat > board.md`
carries no `file_path`, so `guard_verified` never sees it and `Target.for`
returns nothing to check. Without the shell door the whole trust layer is one
`bash -c` away from being off, which is the shape every defect in this gem has
had: not a wrong answer, a *no* answer wearing the costume of a clean one.

The write verbs the guards are protecting are [the-writers](/structure/the-writers.md).

That is also why the write verbs refuse text spanning lines rather than
escaping it — a verb invoked through Bash is seen by neither guard, so the
safety there is by construction rather than by inspection.
