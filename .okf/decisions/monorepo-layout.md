---
type: Constraint
title: The monorepo layout
description: Every gem under gems/, each directory named for the gem it ships; everything that is not a gem stays at the root.
tags: [packaging, repo, portability]
generated:
  by: human:maintainer
  at: 2026-07-24T12:00:00Z
resource: Rakefile
sources:
  - title: Rakefile
    resource: https://github.com/serradura/okf-gem/blob/main/Rakefile
  - title: gems/okf/okf.gemspec
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/okf.gemspec
  - title: gems/okf/test/unit/packaging_test.rb
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/test/unit/packaging_test.rb
---

# Overview

The repository holds more than one gem. **Every gem lives under `gems/`**, and
`gems/okf` is the baseline — the all-in-one that reads, validates, lints,
searches and serves bundles — with the ecosystem beside it as siblings: an MCP
shell, a TUI, an enforcement layer, an FTS5 storage engine.

The rule is that **a directory is named for the gem it ships**. `gems/okf`
builds `okf`, `gems/okf-mcp` builds `okf-mcp`. Nothing has to be mapped or
remembered: a gem's directory, its release-tag prefix, its CI job name and its
`require` path are all the same word. The container names *where gems live*; it
never names *which gem this is*, which is what lets it sit above the rule
without touching it.

The counter-proposal was a role name — `base/`, `kernel/` — which reads better in
a tree and then costs a mapping at every one of those four places. That one is
still rejected.

The tree's asymmetry is information: unprefixed is the host command, prefixed is
a plugin on its seam. `gems/okf` beside `gems/okf-mcp` is the identical
asymmetry one segment deeper, which is why the move renamed nothing.

# What stays at the root

Everything that is not a gem, and one thing that is not obvious:

- `plugin/` and `.claude-plugin/` — the Claude Code plugin and the marketplace
  manifest that names `./plugin`. That path is published; moving it would break
  installs to no end.
- `skills/` — the name every generic skill installer walks. It carries a
  generated copy of okf's skill (agent skill (`@okf capabilities/agent-skill`))
  and okf-principles, whose canonical copy this is: that one describes how to
  structure instructions, not how okf works, so it belongs to no gem.
- `.okf/` — this bundle. It documents the *project*, not the gem, and it grows
  to cover the siblings.
- `Dockerfile` — because its build context must be the repository root. The
  gemspec derives `spec.files` from `git ls-files`, which needs the `.git` only
  the root has, so the image builds `gems/okf/` from a root context rather than
  living inside it.
- `resources/` — the bucket for what is neither a gem nor a distribution
  channel, nested kind-then-platform (`resources/ci/github/`).
- `.okf-registry.json` — every bundle in the tree, addressable as `@slug`.

**A top-level name is either forced by an external consumer, or it goes in
`resources/`.** `plugin/`, `.claude-plugin/` and `skills/` are forced — a
published marketplace path, an installer's discovery walk. Without that rule
every new kind of artifact argues for its own root entry in its own PR, which is
how a root grows to twenty lines and stops being a map.

The extension points (`@okf-eco design/extension-points`) convention is what makes the sibling
gems possible at all; this concept is only about where they sit.

# `gems/` reverses a rejection this concept recorded

This file used to reject the container outright: *a `gems/` container buys
separation the root does not yet need **at this size** while adding a path
segment to every CI path, doc link and citation.* Both halves moved, and the
clause that dated it was *at this size*.

The size is no longer four directories. It is four gems, three root-level
distribution surfaces that are not gems (`plugin/`, `.claude-plugin/`,
`skills/`), a fourth in `resources/`, and a bundle that is the map of the rest.
At that count the root's job stops being "hold the gems" and becomes "hold
everything that is not one" — and the gems are the crowd. The tree is also read
by whoever does not read prose: an agent cloning this repository sees
directories before it sees a paragraph, and a flat root said *one gem plus three
hangers-on*.

The path segment is the real cost and it is paid, not avoided: every CI path,
every `working-directory:`, four `changelog_uri`s and 52 citation URLs gained a
segment in one pass.

The judgement did not turn out wrong. It turned out **conditional, with the
condition written into it**, which is the only reason reversing it is a reshape
rather than a contradiction — and it is the reason to keep writing decisions
that way. A decision worth keeping says what would change it.

# Four mechanisms resolved paths from the root, and three failed quietly

Moving a gem down one level is mechanical. What is not is that most of the
machinery around it resolves paths from the repository root, and only one of the
four says so when it stops working.

**`spec.files` needed nothing.** `git ls-files` with `chdir:` returns paths
relative to the directory it runs in, so the gemspec sees its own tree and
nothing above it. Everything at the root is invisible to it by construction —
which also means its reject list shrank from fourteen prefixes to six, the eight
removed having been rejecting paths that are no longer under the gem.

**`.gitignore` failed silently.** Every *anchored* entry — sixteen of the
nineteen, everything with a leading `/` — stopped matching at once, and the first
test run would have staged a coverage report. (`*.gem` and `Gemfile.lock` carry
no anchor and kept working, which is exactly what made the breakage partial and
therefore easy to miss.) Gem-level entries live in the gem's own `.gitignore`
now, where a leading `/` anchors to the gem.

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
is a trap worth recording — with the detail that matters being *which* half of
the support matrix it breaks on.

`gem build` does **not** resolve the link. It writes it into the package tar as a
symlink, prints `WARNING: LICENSE.txt is a symlink, which is not supported on all
platforms`, and succeeds. What happens next depends on the installer's RubyGems:

- **RubyGems >= 3.2** (Ruby 3.0 and up) refuses to extract a symlink pointing
  outside the gem — `Gem::Package::SymlinkError`. `gem install` fails outright.
- **RubyGems < 3.2** has no such guard. Measured on Ruby 2.7 (RubyGems 3.1.6),
  which is inside this gem's supported range (`@okf design/ruby-floor`): `gem install`
  **succeeds**, exit 0, and installs a dangling `LICENSE.txt` pointing at a path
  that does not exist on that machine.

The older half is the worse one, which inverts the intuition: the failure there
is not a refusal but a gem that installs cleanly and ships no licence. And a
build warning is the only notice either way — `spec.files` lists the file and
`gem contents` reads right.

So they are real duplicated files, with a test asserting they are byte-identical
to the root's and that neither is a symlink. A per-package license copy is what
every other monorepo does anyway; the assertion is what makes the duplication
safe rather than merely conventional.

# The bare tag series stays with the base gem

`rake release` from `gems/okf/` tags `vX.Y.Z`, unprefixed, continuing the series
the gem has published since 1.0. A sibling tags `okf-mcp/vX.Y.Z`.

The asymmetry is deliberate and it pays for itself once: the Docker workflow
triggers on `v*`, and a glob does not match across `/`, so a sibling's release
cannot fire a build of an image that ships something else. Prefixing everything
would have been tidier and would have ended a public tag series mid-history to
buy nothing.

Releases are cut from the gem's own directory — Bundler reads the gemspec in its
working directory and derives the tag from it — so the root `rake release`
refuses rather than doing something plausible.

**`GemHelper#tag_prefix=` is not in every Bundler the matrix runs on.** It
arrived in Bundler 2.2; the Bundler each old Ruby *ships* predates it — 1.17.3 on
2.4 and 2.5, 1.17.2 on 2.6, 2.1.4 on 2.7 — so calling it there raises
`NoMethodError` at Rakefile load, taking `rake test` down with it before a single
test runs. CI hides this, because `ruby/setup-ruby` installs the newest Bundler
each Ruby accepts rather than the bundled one; the 2.4 floor run (`@okf design/ruby-floor`), which uses the image as it comes, is what surfaced it in
okf-tui.

The guard is a `respond_to?`, and what it does in the negative branch is the
point: it defines a `release` task that **aborts**, rather than installing the
real one without a prefix. An old Ruby is one to test on, never one to release
from, so the tasks are absent there rather than present and wrong — a bare
`vX.Y.Z` pushed by accident triggers an image build for a different gem, and no
part of that is undoable.

# A sibling keeps no repo-level half

Files that are the root's live only at the root: a sibling gem carries no CI
workflow, no code of conduct, no `.claude/`, and no independently worded legal
files. Each would be a duplicate of something the repository already owns, and a
duplicate is a drift waiting for a reader. Three of the obligations are
load-bearing rather than tidy:

- **CI is a job in the root's workflow**, never a second workflow file. One job
  per gem with `working-directory:` set on both the job and `ruby/setup-ruby`
  (the action needs its own input to find the Gemfile it caches against).
- **`NOTICE` and `LICENSE.txt` are byte-identical duplicates of the root's**,
  which the section above explains and each gem's packaging test pins. The rule
  admits no locally reworded variant, however defensible: the point is that the
  copies cannot drift, and an exception is a drift with a reason attached.
- **The root's `.rubocop.yml` excludes every gem**, which is how "every gem
  lints itself through its own config" is actually implemented. It used to be a
  four-entry enumeration, and it silently failed to hold: `okf-mcp/` was absent
  from it from the day it landed, so the repo-level lint had been re-checking
  that gem's whole tree against okf's 2.4 target the entire time. It passed,
  which is why nobody noticed. Under `gems/` the enumeration collapses to one
  `gems/**/*` entry and a fifth gem excludes itself — a rule enforced by an
  enumeration is only as true as the last person to remember it, so the fix is
  to stop enumerating rather than to remember harder.

The Gemfile's path source is the fourth. A sibling names the kernel checkout
unconditionally — `gem "okf", path: "../okf"` — because here the checkout is
always next door, and that line is what lets a kernel change be driven from a
shell without a release. The cost is a checkout-versus-RubyGems gap: every
suite — local, CI, the floor container — resolves the checkout, and nothing
crosses to RubyGems by default. So a sibling keeps a scripted run against the
published kernel, and a test pinning that its declared floor never lags the
kernel it develops against.
