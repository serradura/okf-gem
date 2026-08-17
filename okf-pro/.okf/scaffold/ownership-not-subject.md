---
type: Decision
title: The scaffold splits by ownership, not by subject
description: Knowledge-versus-machinery is the obvious cut and the wrong one — it makes `upgrade` destroy exactly the hand-merge that adopting the gem asked for.
---

# The two classes

**Gem-owned** — the hook wrapper, the pre-commit hook, the CI workflow, the
skill. These carry [the contract](/contract/the-contract.md) and the exit-code
protocol, so they must track the gem or a gate goes quietly wrong. `upgrade`
rewrites them outright.

**Seeded** — `README.md`, `CLAUDE.md`, `.gitignore`, `.claude/settings.json`,
and the whole of `.okf/`. Written once, and the adopter's from that moment.

# Why the obvious cut is wrong

Sorting by subject matter — knowledge in one pile, machinery in the other — puts
`CLAUDE.md`, `.gitignore` and `settings.json` on the machinery side, because
that is what they look like. Then `upgrade` overwrites them.

But `CLAUDE.md` at a repository root is the adopter's agent-instruction file;
`.gitignore` accumulates project entries from day one; `settings.json` is where
they add hooks of their own. Every one of them is a file the scaffold's own
instructions tell them to merge into. An upgrade that rewrote them would destroy
exactly the work adopting this thing asked for — and would do it on the run
after the one where they did it.

The question is not *what is this file about*. It is *whose file is it once it
exists*.

# The two front doors say the same thing twice, deliberately

`README.md` and `CLAUDE.md` both describe the three doors, in nearly the same
words. That is not drift waiting to be collapsed, and the argument for
collapsing it is a real one that has to be answered rather than ignored: one
operative copy beats two agreeing copies until the day they stop agreeing, and
this bundle applies that rule everywhere else.

It does not apply here, because these two files have **different readers and no
shared moment**. `CLAUDE.md` is loaded by an agent at the start of every session
that touches the bundle; `README.md` is read by a person, once, on the day they
arrive. Neither reader sees the other's file, so a pointer from one to the other
is a dead end rather than a single source: the agent will not follow a link to
prose written for a human, and the human should not have to read the agent's
instructions to learn how to arm a git hook.

What the rule actually forbids is two copies of a *fact that changes* — a count,
a path, a version. The doors are a fixed shape, and each file states them for
its own reader in its own register. The seeded files are the adopter's from the
moment they are written ([nothing rewrites them](/scaffold/no-date-ships.md)),
so even a real divergence stays local to one repository rather than shipping.

# The `.okf/` exemption

Seeded files are staged beside the adopter's as `<path>.okf-pro-new` on a
collision — except inside `.okf/`, where only missing files are added.

A bundle that exists is a bundle already adopted, and eleven shadow files
scattered through someone's knowledge is not a merge prompt, it is litter — in
the one directory whose entire value is that everything in it was put there
deliberately.
