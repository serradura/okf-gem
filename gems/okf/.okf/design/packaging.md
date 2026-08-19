---
type: Constraint
title: "What ships, and the two ways it has gone wrong"
description: "`spec.files` is `git ls-files` minus a reject list, which makes `.dockerignore` imply the gemspec one way only — and a symlink in the package installs dangling on the old half of the supported matrix rather than failing."
resource: gems/okf/okf.gemspec
tags: [packaging, gemspec, docker, rubygems]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: RubyGems Gem::Package::SymlinkError
    resource: https://github.com/rubygems/rubygems/blob/master/lib/rubygems/package.rb
---

# The list is subtractive

`spec.files` comes from `git ls-files` run with `chdir:` into the gem's own
directory, minus a reject list: `test/`, `bin/`, the Gemfile, the Rakefile,
`.gitignore`, `.rubocop.yml`, `AGENTS.md`, `CLAUDE.md`, and the gemspec itself.

Two consequences follow from it being subtractive rather than additive.
Everything at the repository root is invisible to it, so a new *root* file needs
no reject at all. But a new top-level file **inside the gem** ships unless the
gemspec rejects it — check `gem build` output when adding one.

`.okf/` is deliberately not rejected: an installed okf carries a real bundle, its
own — the [companion skill](../capabilities/agent-skill.md) ships the same way,
from `lib/okf/skill/`, for a reader to open with the tool they just installed.
`test/unit/packaging_test.rb` pins that it ships, and pins that `AGENTS.md` and
`CLAUDE.md` do not — the guide is for someone with a checkout, and `CLAUDE.md`
is one line pointing at it, so shipping the pointer without its target puts a
reference to nothing inside the published gem.

# `.dockerignore` implies the reject list, one way only

Anything `.dockerignore` drops from under the gem's directory must **also** be
rejected by the gemspec, or be gitignored. `git ls-files` reads the *index*, so
a path excluded from the Docker build context is still listed in `spec.files`,
and `gem build` then fails on a file that is not there.

**The converse does not hold, and must not be "restored" for symmetry.** `bin/`,
`Gemfile` and `Rakefile` are rejected from the gem and stay in the build context
on purpose; nothing breaks by shipping them to the builder.

One detail that looks like a bug and is not: `.dockerignore`'s bare `.okf` entry
drops the *repository's* bundle, not this gem's, because Docker anchors a
pattern with no `**` at the context root.

# Nothing in `spec.files` may be a symlink

`gem build` does not resolve one. It writes a symlink into the package, warns,
and succeeds.

What happens next depends on the installer's age, and the old half of the
supported matrix is the dangerous half. RubyGems >= 3.2 refuses to extract a
link pointing outside the gem (`Gem::Package::SymlinkError`) — loud, and
survivable. **RubyGems < 3.2 has no guard at all**, so on Ruby 2.7 (RubyGems
3.1.6, inside the supported range) `gem install` exits 0 and installs a
*dangling* file. The gem installs cleanly and carries no licence, and nothing
says so.

So `LICENSE.txt` and `NOTICE` are real duplicates of the repository root's
rather than links to them, and `test/unit/packaging_test.rb` pins three separate
claims: that they are not symlinks, that they are byte-identical to the root's,
and that they are actually in `spec.files`.
