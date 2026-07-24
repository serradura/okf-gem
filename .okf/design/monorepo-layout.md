---
type: Constraint
title: The monorepo layout
description: One directory per gem, named for the gem; everything that is not a gem stays at the root.
tags: [packaging, repo, portability]
timestamp: 2026-07-24T12:00:00Z
resource: Rakefile
---

# Overview

The repository holds more than one gem. `okf/` is the baseline — the all-in-one
that reads, validates, lints, searches and serves bundles — and the ecosystem
grows beside it as siblings: an MCP shell, a TUI, an FTS5 storage engine.

The rule is that **a directory is named for the gem it ships**. `okf/` builds
`okf`, `okf-mcp/` builds `okf-mcp`. Nothing has to be mapped or remembered: a
gem's directory, its release-tag prefix, its CI job name and its `require` path
are all the same word. It is the layout Rails uses for the same reason.

The counter-proposal was a role name — `base/`, `kernel/` — which reads better in
a tree and then costs a mapping at every one of those four places. A `gems/`
container was the other, and it buys separation the root does not yet need at
this size while adding a path segment to every CI path, doc link and citation.

# What stays at the root

Everything that is not a gem, and one thing that is not obvious:

- `plugin/` and `.claude-plugin/` — the Claude Code plugin and the marketplace
  manifest that names `./plugin`. That path is published; moving it would break
  installs to no end.
- `.okf/` — this bundle. It documents the *project*, not the gem, and it grows
  to cover the siblings.
- `Dockerfile` — because its build context must be the repository root. The
  gemspec derives `spec.files` from `git ls-files`, which needs the `.git` only
  the root has, so the image builds `okf/` from a root context rather than
  living inside it.

The [extension points](extension-points.md) convention is what makes the sibling
gems possible at all; this concept is only about where they sit.

# Four mechanisms resolved paths from the root, and three failed quietly

Moving a gem down one level is mechanical. What is not is that most of the
machinery around it resolves paths from the repository root, and only one of the
four says so when it stops working.

**`spec.files` needed nothing.** `git ls-files` with `chdir:` returns paths
relative to the directory it runs in, so the gemspec sees its own tree and
nothing above it. Everything at the root is invisible to it by construction —
which also means its reject list shrank, because seven of its entries had been
rejecting paths that are no longer under the gem.

**`.gitignore` failed silently.** Every entry was root-anchored, so all of them
stopped matching at once and the first test run would have staged a coverage
report. Gem-level entries live in the gem's own `.gitignore` now, where a
leading `/` anchors to the gem.

**SimpleCov failed silently, and in the direction that looks like success.** Its
root defaults to the working directory, so the plugin's curation hook — a
repo-level file the suite tests — fell outside it and its ~100 lines left the
report. Line coverage read 98.63% against 98.47%: the percentage went *up* while
the thing being measured got smaller. Its root is the repo now, its
`coverage_dir` absolute so the report still lands in the gem.

**`.dockerignore` fails loudly, and pairs with the gemspec.** Its entries were
root-relative too, but the invariant underneath is the durable part:
whatever it drops from under the gem must also be in the gemspec's reject list.
`git ls-files` reads the *index*, so a path excluded from the build context is
still listed in `spec.files`, and `gem build` then fails on a file that is not
there. The two lists move together.

The lesson generalizes past this move: **a path resolved from an implicit root
is a dependency on where you are standing**, and the ones that degrade quietly —
an ignore file, a coverage root — are worse than the ones that crash.

# A symlinked LICENSE ships a gem nobody can install

The gem must distribute `LICENSE.txt` and `NOTICE`, and `git ls-files` from the
gem directory cannot see the root's copies. The obvious fix is a symlink, and it
is a trap worth recording because every signal says it worked:

`gem build` does **not** resolve the link. It writes it into the package tar as
a symlink, and RubyGems refuses to extract one pointing outside the gem —
`Gem::Package::SymlinkError`. The build succeeds. `spec.files` lists the file.
`gem contents` looks right. The failure lands on a stranger's machine at
`gem install`, after the release is public.

So they are real duplicated files, with a test asserting they are byte-identical
to the root's and that neither is a symlink. A per-package license copy is what
every other monorepo does anyway; the assertion is what makes the duplication
safe rather than merely conventional.

# The bare tag series stays with the base gem

`rake release` from `okf/` tags `vX.Y.Z`, unprefixed, continuing the series the
gem has published since 1.0. A sibling tags `okf-mcp/vX.Y.Z`.

The asymmetry is deliberate and it pays for itself once: the Docker workflow
triggers on `v*`, and a glob does not match across `/`, so a sibling's release
cannot fire a build of an image that ships something else. Prefixing everything
would have been tidier and would have ended a public tag series mid-history to
buy nothing.

Releases are cut from the gem's own directory — Bundler reads the gemspec in its
working directory and derives the tag from it — so the root `rake release`
refuses rather than doing something plausible.

# Citations

[1] [Rakefile](https://github.com/serradura/okf-gem/blob/main/Rakefile) — the root delegator and the `GEMS` list a new gem is added to.
[2] [okf/okf.gemspec](https://github.com/serradura/okf-gem/blob/main/okf/okf.gemspec) — `chdir:` on `git ls-files`, and the reject list paired with `.dockerignore`.
[3] [okf/test/unit/packaging_test.rb](https://github.com/serradura/okf-gem/blob/main/okf/test/unit/packaging_test.rb) — the assertions that keep the license copies real and identical.
