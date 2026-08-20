---
type: Runbook
title: The CI Matrix and What Only It Catches
description: Ten Rubies on every push, what only the 2.4 container proves, and the resolution gap the matrix cannot see because every run resolves the sibling checkout.
tags: [testing, ruby-floor, dependencies]
generated:
  by: human:maintainer
  at: 2026-07-19
sources:
  - title: "The repository's `.github/workflows/main.yml`, `okf-tui` job."
    resource: https://github.com/serradura/okf/blob/main/.github/workflows/main.yml
  - title: "`AGENTS.md` — the scripted `Gemfile.ci-check` run against the published okf."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/AGENTS.md
---

# The matrix

The repository's `.github/workflows/main.yml` runs this gem's default task on
Ruby 2.4 through 4.0 as its own `okf-tui` job — 2.4/2.5/2.6 on `ubuntu-22.04`,
the rest on `ubuntu-latest`, since the older Rubies predate the current image's
toolchain. `fail-fast: false`, so one failure does not hide the others. It is one
job per gem rather than a gem axis on one matrix, because the gems in the
repository do not share a Ruby floor. A change is not done until the matrix is
green.

The floor can also be proven locally, which is faster than pushing. Run it from
the repository root and let it step in here — the Gemfile resolves okf from
`../okf`, so a container holding only this directory fails at `bundle install`
before a test runs:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/okf-tui && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

The copy and the dropped lockfile are both load-bearing: a lockfile written by a
modern Bundler is one 2.4's own cannot read, and mounting read-only stops the run
writing one back.

**This container runs an older Bundler than CI does, and that is a feature.**
`ruby/setup-ruby` installs the newest Bundler each Ruby accepts; the image ships
the one the Ruby came with — 1.17.3 on 2.4. The gap is a real support claim, and
it caught a Rakefile that could not *load* there: `GemHelper#tag_prefix=` arrived
in Bundler 2.2, so the line that keeps this gem's release tags prefixed raised
`NoMethodError` before `rake test` reached a test. The matrix would have been
green over it.

# What the matrix cannot catch

A green run proves the code against the okf on this disk, not the okf a user
gets: the Gemfile resolves the kernel from the checkout next door, so every run
— local, CI, the floor container — exercises the *unreleased* kernel, and
nothing crosses to RubyGems by default. When two runs of identical code
disagree, suspect dependency resolution before suspecting the runner.

Two things stand in that gap, and they cover different halves:

- `test/unit/gemspec_test.rb` fails the moment okf bumps and the gemspec's
  declared floor does not follow, so the floor can never quietly come to admit a
  kernel this code has outgrown.
- A scripted run against the *published* okf catches what a floor cannot
  express, which is that a released kernel returns different analysis output:

  ```bash
  sed '/gem "okf", path:/d' Gemfile > Gemfile.ci-check
  BUNDLE_GEMFILE=Gemfile.ci-check bundle install && BUNDLE_GEMFILE=Gemfile.ci-check bundle exec rake
  ```

Run it before pushing anything that reads okf's analysis, and before a release.
Nothing enforces it, which is the honest state: it is a maintainer obligation,
and saying so is better than believing the matrix covers it.

Two details keep that reproduction honest:

- **`Gemfile.lock` is gitignored**, so there is no committed resolution to mask
  a broken one — every run re-resolves.
- **A plain `cp` of the tree keeps the untracked lockfile**, and that lockfile
  can carry a `PATH` remote naming an absolute directory on this machine — so a
  copy made to test the published resolution can quietly resolve against
  something no user has. Drop the lockfile in the copy, exactly as the Docker
  command above drops it for its own reason (a lockfile written by a modern
  Bundler is one 2.4's cannot read).
