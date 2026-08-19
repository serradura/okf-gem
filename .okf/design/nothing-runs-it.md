---
type: Constraint
title: A rule nothing runs
description: Every convention here is either executed by something or is a wish, and this repository has twice written down that a rule was enforced when nothing ran it.
tags: [governance, ci, enforcement, honesty]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: .github/workflows/main.yml
    resource: https://github.com/serradura/okf-gem/blob/main/.github/workflows/main.yml
---

# The failure, twice

**Once in CI.** The root `.rubocop.yml` inherits the kernel's and covers the two
Ruby files that sit outside every gem. A commit described that as "restoring
lint coverage" — and in CI nothing ran it, because no gem's `rake rubocop`
reaches a file outside every gem. The claim was in the repository, false, for as
long as nobody checked. A single `lint` job on one modern Ruby is what made it
true.

**Once in a document.** A maintainer guide carried a hand-written map of a
gem's `lib/` and nothing compared it to the tree. It was accurate when written
and would have stayed *plausible* forever afterwards, which is the dangerous
property: a wrong map does not look wrong.

# The rule

Every convention is in one of two states, and it must be obvious which:

1. **Executed** — a test, a rake task a build depends on, a CI job. Then say
   what runs it, so a reader can go look.
2. **A maintainer obligation** — then say *that*, plainly, and say that nothing
   enforces it.

What is forbidden is the third state: prose that reads as if something checks,
where nothing does.

# The obligations this repository states as unenforced

They are real, and naming them is the point:

* the browser suite for the graph page — deliberately out of CI, on measured
  evidence that a usually-red check teaches its readers to ignore it;
* the Ruby floor Docker runs;
* the PR title, label and body shape — no CI check reads a pull request;
* a new verb's line in its gem's README.

A check that is usually red is worse than no check, because it trains its
audience. Removing one is sometimes the honest move — but only alongside the
sentence saying the obligation is now a person's.
