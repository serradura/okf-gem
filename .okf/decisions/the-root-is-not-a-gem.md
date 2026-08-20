---
type: Decision
title: The root is not a gem
description: There is no root Gemfile because the gems do not share a Ruby floor and one lockfile could never resolve for all of them — which decides how `rake` delegates, why a release refuses at the root, and why the repo-level Ruby needed a CI job of its own.
tags: [monorepo, tooling, ci, rake, bundler]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: Rakefile
    resource: https://github.com/serradura/okf/blob/main/Rakefile
  - title: .github/workflows/main.yml
    resource: https://github.com/serradura/okf/blob/main/.github/workflows/main.yml
---

# There is no root Gemfile

The four gems do not share a Ruby floor — okf, okf-tui and okf-pro sit at 2.4,
okf-mcp at 2.7, which it inherits from the `mcp` SDK. One lockfile could never
resolve for all of them, so there is none, and everything below follows from
that.

**The root `Rakefile` runs plain `rake`, not `bundle exec rake`.** `bundle exec
rake` at the root fails with "Could not locate Gemfile", and that is the
intended answer rather than an oversight.

**It names each gem's `BUNDLE_GEMFILE` explicitly when it delegates.** Bundler
exports that variable to everything it runs, so a nested `bundle exec` otherwise
inherits the parent's bundle and a gem's task quietly resolves the wrong
dependency set.

**`rake release` at the root refuses.** Bundler reads the gemspec in its working
directory and derives the tag from it, so a release cut from the root would do
something plausible and wrong. It is cut from the gem's own directory — the tag
convention that goes with it is [releases and tags](release-and-tags.md).

# The repo-level Ruby had no owner

Two Ruby files sit outside every gem: the root `Rakefile` and the plugin's
curation hook, `plugin/hooks/scripts/curate.rb`. No gem's `rake rubocop` reaches
a file outside that gem, so for a while nothing linted either of them.

The root `.rubocop.yml` inherits the baseline gem's and covers exactly those two
files, and a single `lint` job in CI runs the root `rake rubocop` on one modern
Ruby. That job is the only thing standing between the curation hook and being
linted by nobody. Before it existed this repository shipped a commit claiming
the root `.rubocop.yml` "restores lint coverage" when in CI it did nothing at
all — which is the instance behind
[a rule nothing runs](../design/nothing-runs-it.md) .

# CI is one job per gem

Not a gem axis on one matrix: the floors diverge, so a shared matrix would be
mostly exclusions. Each job sets `working-directory` on both the job and
`ruby/setup-ruby` — the action needs its own input to find the Gemfile it caches
against, and setting it only on the job caches against nothing.

A change is not done until the gem's job and the `lint` job are both green.
