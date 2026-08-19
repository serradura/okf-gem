# Decisions

Choices that could have gone otherwise, each with the argument that settled it
and the cost it accepted. The [design](../design/) area holds the structure
these are arranged against; this one holds the forks.

A decision here is reversible in principle. What it earns is that reversing it
starts from the argument rather than from scratch.

* [The monorepo layout](monorepo-layout.md) - Why every gem lives under `gems/`, what earns a top-level name, and the reversal this reverses.
* [One door per sibling](one-door-per-sibling.md) - Three gems ship no executable and arrive as an `okf` verb; adding a binary back needs an argument stronger than symmetry.
* [Releases and tags](release-and-tags.md) - The bare `v*` series belongs to the baseline and a sibling qualifies itself, because a glob does not match across `/`.
* [A gem's structure is a bundle](structure-is-a-bundle.md) - The `lib/**` map moved out of every maintainer guide and into a bundle a test can hold to the tree.
* [The root is not a gem](the-root-is-not-a-gem.md) - There is no root Gemfile, which decides how `rake` delegates, why a release refuses at the root, and why the repo-level Ruby needed its own CI job.
