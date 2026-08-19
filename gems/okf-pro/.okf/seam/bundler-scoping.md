---
type: Finding
title: Bundler scoping switches the gates off, and the fix locks out the in-bundle adopter
description: Gem discovery is bundle-scoped once bundler's variables are exported, so `okf pro` is an unknown command inside a bundle that does not name okf-pro.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# Both directions, both measured

okf finds its extensions with `Gem.find_latest_files`, which is bundle-scoped
once bundler's variables are in the environment.

```
BUNDLE_GEMFILE=gems/okf/Gemfile bundle exec okf tui --help
→ unknown command, exit 2
```

An agent working inside any bundled Ruby project would find every gate silently
absent. But the repair has a mirror image: **inside a bundle,
`Gem.find_latest_files("okf/plugin.rb")` returns `[]` outright**. A repository
that deliberately vendors okf-pro through its own Gemfile is served *only* by
the un-stripped run, so a wrapper that sanitised up front would lock it out of
its own checker.

The wrapper therefore tries un-stripped **first** and falls back to stripped,
with `OKF_PRO_NO_UNBUNDLE=1` to pin the first. Both directions are drilled.

Both branches live in [the wrapper](/seam/the-wrapper.md), which is the only
place that can act before okf starts.

# The variable list was wrong, and any list would be

A first attempt stripped `BUNDLE_GEMFILE`, `BUNDLE_PATH` and `BUNDLE_BIN_PATH`.
Bisected: `BUNDLE_PATH` and `BUNDLE_BIN_PATH` are inert, and the two that matter
are `RUBYOPT` and `BUNDLER_SETUP`. `BUNDLER_SETUP` is recent enough that naming
it is a bet on the adopter's bundler version — on a gem whose Ruby floor is 2.4.

So the wrapper uses bundler's **own** restoration data, the `BUNDLER_ORIG_*`
variables it exports for exactly this purpose, and is version-proof by
construction rather than by an enumeration someone has to maintain.

# The general shape

When a dependency already records how to undo what it did, use that record. A
hand-written inverse of somebody else's transformation is correct only for the
versions you tested.
