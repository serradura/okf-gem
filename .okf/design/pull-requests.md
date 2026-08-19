---
type: Playbook
title: The shape of a pull request
description: Every PR is a written argument for its own diff — a lead, sections named for what they settle, and a Verification section carrying real numbers — and a version bump adds a fixed title and body on top.
tags: [governance, review, release, process]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: The merged pull requests
    resource: https://github.com/serradura/okf-gem/pulls?q=is%3Apr+is%3Aclosed
---

# The skeleton

Every PR is a written argument for its own diff, and they share one skeleton.
#12, #7 and #15 are good instances of it at three sizes.

1. **A lead paragraph, no heading** — what changes and why, in a sentence or
   three, carrying the issue it settles (`Closes #6.`, `Follow-up to #7.`). A
   reviewer who reads only this must know whether the PR concerns them. Do not
   open with a `## What` or `## Summary` heading: the first paragraph is already
   the summary, and the heading only pushes it below the fold.
2. **`##` sections named for the area they change or the question they settle** —
   "Where the wrap lives", "The design — one template, two modes", "Graph page".
   Named for their content, not their role: "What", "Overview" and "Details"
   read the same on every PR and tell a reviewer nothing about where to skip to.
   A small PR (#8) needs none at all — a lead and a list is a complete body.
3. **`## Verification` last** — the commands actually run, with their real
   numbers.

**Argue, don't restate.** The diff is one tab away and reviewers can read it; a
body that inventories changed files earns nothing. Spend the space on what the
diff cannot say: the alternative rejected and why (#12 on why the wrap sits at
the boot seam and not in `App`), the bug class a test pins (#12's wiring pin),
the measurement behind a trade-off, the constraint the change had to hold — the
runtime-dependency rule, the 2.4 floor, the core/shell split.

The prose is the maintainer's, under the same attribution rule as commits.

# Verification, and the three rules that outrank its formatting

- **A skipped check is stated as skipped, with why.** #1's "Not run: the Ruby
  2.4 Docker floor…" is the model. A bullet nobody ran is worse than no bullet,
  because it spends the reviewer's trust rather than earning it.
- **A claim carries the evidence it came from** — "~86% (9.7 KB → 1.4 KB)",
  "worst pairwise gap -1px → +39px", not "much smaller" or "better spaced". If
  it was measured, print the measurement.
- **What can only prove out after merge gets its own section** ("After merge"),
  never a Verification bullet — publishing a demo, uploading an image, running a
  workflow.

# A release PR adds three fixed things

**A PR that touches a gem's `version.rb` is a release PR.** It is everything
above, plus the `release` label and the two fixed shapes below. PRs #1–#15 were
normalized to all three in one pass, so the merged list reads as one series —
match it. The label is what keeps the series queryable
(`gh pr list --state all --label release`) when a title is mistyped.

## The title

```
Release X.Y.Z — <summary>              # the baseline gem
Release <gem> X.Y.Z — <summary>        # a sibling: Release okf-mcp 1.0.0 — …
```

- **`Release X.Y.Z` verbatim** — the literal word, the bare version, no `v`, no
  branch prefix, and never parenthesized at the end. This holds even when the
  bump is not the point of the work; the release a version shipped in should be
  findable by scanning one column.
- **A sibling names its gem, immediately after `Release`** — the same asymmetry
  [the tags already carry](../decisions/release-and-tags.md), and for the same
  reason: the baseline owns the bare series and a sibling qualifies itself. The
  gem goes in the title, not in the summary — `gh pr list --label release` has
  to answer *which gem, which version* by column, and a name buried after the em
  dash does not.
- **A spaced em dash** — not a colon, not a hyphen. The summary is a phrase, not
  a subtitle.
- **The summary is the CHANGELOG's headline** — the two or three things the new
  section leads with, comma-joined, lowercase but for identifiers and proper
  nouns, no trailing period, one line (past ~80 characters it is listing too
  much). "opt-in search index, the graph's index layer, @slug addressing", not
  "This release adds an opt-in search index."

## The body

The skeleton above, pinned at three points:

- **The lead opens with the cut** — `Cuts **X.Y.Z**.` — and closes with the
  pointer: `CHANGELOG.md` carries the full notes under `## [X.Y.Z] -
  YYYY-MM-DD`. The PR argues the release, the CHANGELOG itemizes it, so the lead
  says what the version is *for* and never re-lists the entries.
- **Verification names the release checks**: `rake`, the floor container,
  `skill:verify` where the gem has one, `gem build`, and `validate`/`lint` on
  the repository's own bundles.
- **The closing line, verbatim**: `` `rake release` (tag, push, RubyGems with
  MFA) is deliberately not run here. `` — the PR is the gate, the human pushes
  the gem.

#15 is the reference instance of both shapes. Nothing enforces any of it — no CI
check reads PR titles or bodies — so it is a maintainer obligation held by [the
same rule as every other unrun convention](nothing-runs-it.md). The point of it
is that the tag, the CHANGELOG entry and the PR that carried them stay findable
as one thing. A PR with no version bump takes the base skeleton only: no label,
no fixed title (#12, #8, #7).
