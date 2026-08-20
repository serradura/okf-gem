---
type: Constraint
title: How a change is proven
description: Four obligations that hold in every gem regardless of its floor or its layers — the test comes first and must be read failing, assertions must be able to fail for a real reason, structural documentation is pinned rather than trusted, and the bundle ships in the same commit as the code.
tags: [testing, governance, review, process]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: The gems' maintainer guides
    resource: https://github.com/serradura/okf/tree/main/gems
---

# The four

Which layer is *critical* differs by gem — the CLI's is `test/integration/cli/`,
okf-pro's is a subprocess drill, okf-tui's drives real keys at a headless frame.
These four do not.

**A change starts with a failing test at the level the change lives at**, and
the failure is read, not merely seen: it must fail for the reason you predicted,
not because a fixture is missing or a regex has a typo. Then the code, then the
same test green and **unedited**. A test written after the fix certifies only
the code it was read off, and editing test and code together in one pass is how
a bug and its test come to agree with each other and stay wrong together. A bug
report earns a red test before a patch.

**Pure refactors are the exception, not a licence.** They change no behavior, so
the existing suite is the test and a green run is the proof. If a change is too
small to fail visibly first, say so — never skip the step quietly.

**Assertions must be able to fail for a real reason.** Run the thing, read what
it actually prints, then assert *that*. Never assert what you assume the code
does; that is how a green suite certifies a bug. The strongest form of the same
idea is to break the code on purpose and watch the test report it.

**Do not skimp on fixtures.** When a path is unreachable from the existing ones,
add the fixture; never bend a test toward what the fixtures happen to make easy.
A branch no fixture can reach is a branch nobody has ever proven.

# What is pinned, and what is only written down

Structural documentation is code-derived, which makes it the kind that rots
silently. Every gem's `structure/` area is held to its tree by its own
`test/unit/bundle_catalog_test.rb`: a file under `lib/` that no concept names, a
concept naming a file that is gone, or a catalogue out of step with the constant
it mirrors is a **red suite**, not a stale document. That is
[a gem's structure is a bundle](../decisions/structure-is-a-bundle.md) .

Everything else here is a rule nothing runs, and is held by
[saying so plainly](nothing-runs-it.md) rather than by pretending otherwise.

# The bundle ships with the code

A gem's `.okf/` is maintained in the same commit as the code it documents, not
as a follow-up chore. A durable lesson a change taught goes in the concept it is
about, stated as a principle — the reader finds it there, not by reading
history. Which bundle a given fact belongs to is
[where knowledge lives](where-knowledge-lives.md) .
