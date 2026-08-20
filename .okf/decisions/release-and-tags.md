---
type: Decision
title: Releases and tags
description: The bare `vX.Y.Z` series belongs to the baseline gem and every sibling qualifies itself, because a Docker workflow fires on `v*` and a glob does not match across a slash.
tags: [release, tags, ci, docker, versioning]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: .github/workflows/docker.yml
    resource: https://github.com/serradura/okf/blob/main/.github/workflows/docker.yml
  - title: AGENTS.md — Releasing
    resource: https://github.com/serradura/okf/blob/main/AGENTS.md
---

# The decision

| gem | tag | release PR title |
|---|---|---|
| okf | `vX.Y.Z` | `Release X.Y.Z — <summary>` |
| a sibling | `okf-mcp/vX.Y.Z` | `Release okf-mcp X.Y.Z — <summary>` |

The asymmetry is deliberate. Prefixing everything would have been tidier and
would have ended a public tag series mid-history to buy nothing.

# The reason is mechanical, not aesthetic

The Docker workflow fires on `v*`, and **a glob does not match across `/`**. So
`okf-mcp/v1.2.0` cannot trigger a rebuild of an image that ships something else.

Without the prefix, a sibling's release would republish the `okf` image —
`:latest` included — from a version that contains none of it.

# What the prefix costs, and how it is guarded

`Bundler::GemHelper#tag_prefix=` arrived in **Bundler 2.2**, and Ruby 2.7 ships
2.1.4. A sibling on that floor whose Rakefile sets it unguarded dies with
`NoMethodError` before a single test runs — and CI never sees it, because
`setup-ruby` installs a newer Bundler.

So each sibling's Rakefile asks `respond_to?` first, and where the accessor is
missing it defines a `release` task that **refuses**, naming the reason. A
release from the wrong Ruby stops rather than pushing a bare tag.

# The rest is a maintainer obligation

A PR touching a version file takes the `release` label, the fixed title, and a
body whose lead opens with the cut and closes with the pointer to the CHANGELOG.
Nothing in CI reads a pull request, which is exactly why the shape is written
down — see [a rule nothing runs](../design/nothing-runs-it.md).
