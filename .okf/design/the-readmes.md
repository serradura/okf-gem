---
type: Constraint
title: The READMEs
description: A boundary earns a README when a stranger can land on it directly; the root's is the menu and a gem's is that gem's, and four rules outrank taste because each has already gone wrong here.
tags: [documentation, governance, boundary, readme]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: The repository's READMEs
    resource: https://github.com/serradura/okf/blob/main/README.md
---

# Who gets one

**A boundary gets its own README when a stranger can land on it directly** —
from a search result, a package page, a pasted link. That is true of each of the
four gems and of `resources/ci/github/`, which is the one place someone copies a
file into a pipeline they will run unattended. `gems/` itself needs none: nobody
arrives at a container, they arrive at what it holds.

**The root `README.md` is the menu** — the ecosystem, not any one gem. It is
what GitHub renders and what a link from anywhere lands on, so it carries the
problem statement, the hero and overview diagrams, the comparison table, and one
row per door. It answers "what is OKF and should I care", then names the
boundaries. It does *not* explain how any of them works: a menu that is also a
manual for one item on it is a front door a visitor has to read past.

**Each gem's README is that gem's** — `gems/okf/README.md` ships inside the
`.gem`, and its reader has already decided. Install, the shortest path to a
working bundle, the command block, one worked example per surface. No hero
images: it is read on rubygems.org and in a terminal, where a relative image
path resolves to nothing.

No README here is a symlink or a generated copy of another; they say different
things. Which reader each file is for at all is
[where knowledge lives](where-knowledge-lives.md).

# The first screen has one job

**A reader arrives with a loss, not with a category.** Their agent works the
codebase out every session and forgets it every session, so the top of the page
names that and shows it fixed: the loss, then what the thing is, then a command
they can run against this repository before installing anything, then the
comparison that places it against the homes knowledge already has.

**Feature inventory is not an opening.** The three pieces, the sibling verbs and
the packaging claim are all true and all good, and all of them answer a question
the reader has not asked by line 30. They live below the fold under **The whole
ecosystem**. The same goes for vocabulary: *bundle*, *concept* and *progressive
disclosure* survive, but the first use of *bundle* sits next to a command that
shows one.

The check, asked of someone who has never heard of OKF after reading down to the
end of the sixty-second block: **what would you use this for?** An answer that
describes a use means the order is right. An answer that describes what the
software *is* means it is not, however accurate the description.

# The manual is elsewhere

**The site owns the manual; a README is a front door.** Every verb is
documented at [okfgem.com/docs](https://okfgem.com/docs/), so a README spends
its space on *value and usage* — what this is for, what it buys you, the
shortest path to a working bundle — and links out for the rest. When a passage
starts enumerating flags, spec clauses, API surface or category lists, it has
become reference material: move it to the site and leave a sentence and a link.

What earns its place in the root's, in this order: the loss and the answer to
it, the sixty-second block, why it does not rot, the comparison table, what a
bundle actually looks like, the ecosystem — three pieces and three sibling verbs
— the two diagrams, one row per door, and the install line for the two channels
that have no README of their own, the plugin marketplace and `npx skills`. The
four-step start and the worked examples per surface moved to
`gems/okf/README.md`, where the reader has already decided. What does not:
clause-by-clause §9, the six lint categories enumerated, exhaustive library
listings, a Ruby version matrix, or an essay per flag. The version this replaced
carried all of those; they are all still true and all still one link away.

# Four rules that outrank taste

Each has already gone wrong in this repository.

- **Every command shown must run, exactly as written.** Not "looks right" — run
  it against this repo's own `.okf` and check the exit status. A README whose
  commands have drifted spends a new reader's trust on their first minute.
- **Every number is measured now, not copied.** Byte counts, concept counts and
  timings go stale as fixtures grow. Re-measure before printing, and if it
  cannot be measured, do not print it. The `index --json` figure carried over
  from the CHANGELOG as 311 KB → 2.6 KB and measured 313 KB → 2.8 KB the same
  afternoon — close enough to look fine, wrong enough to be a fabricated number.
- **A deprecated spelling never appears.** After any CLI change, grep the README
  for the flag you just retired. `--area` outlived its deprecation there by a
  whole feature branch.
- **A new verb ships with its README line**, the same obligation as its test
  file. A verb absent from the command block does not exist to a reader. That
  obligation is the *gem's* README's, not the root's — with one exception:
  **a sibling's door is named by the verb it answers to**. `okf mcp`, `okf tui`,
  `okf pro` — one command growing verbs *is* the interface claim, and four gems
  listed without their verbs read as four tools. That belongs under *The whole
  ecosystem*, never in the lead, for the reason above. What never reaches the
  root at all is a gem's *own* verb list: its subcommands, its flags, its
  options. A new gem earns a root row; a new verb inside one is that gem's
  README's problem.

Nothing runs any of these, which is why they are written down as rules rather
than trusted as taste — see [a rule nothing runs](nothing-runs-it.md).

# Three details that are easy to get wrong

**Benchmarks name the shape of what was measured, never where it lives** — "a
400-concept bundle", not a path. Scratch material under the repo root's `tmp/`
is a working reference, not part of the published record, and must not be named
in either README, the CHANGELOG, a bundle, or the skill.

**Alt text carries the whole content of its image.** The hero and overview PNGs
say everything the diagram says, in prose, because the README is read in
terminals, by screen readers, and by agents that never fetch the image.

**Link depth downward, breadth outward.** The root's rows link to the boundary
they name, and its bundle pointers go to the concept documenting a claim — this
project's own knowledge is an OKF bundle, and pointing at it is the argument
that the format works. The manual, the guides and the demo are absolute links to
the site. A gem's README cannot link into its `.okf/` at all: those paths do not
resolve for the reader of an installed gem, so it links to the site or to
nothing.

The prose is the maintainer's, in the README's established voice. Match it
rather than flattening it into neutral documentation register; the same
attribution rule as commits applies.
