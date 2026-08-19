---
type: Component
title: The GitHub CI recipe
description: A workflow anyone can copy to validate and lint their own bundles, with exactly one repository-specific line — and this repository runs the same file, which is what keeps it true.
resource: resources/ci/github
tags: [ci, github, docker, recipe]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: resources/ci/github/okf.yml
    resource: https://github.com/serradura/okf-gem/blob/main/resources/ci/github/okf.yml
  - title: resources/ci/github/README.md
    resource: https://github.com/serradura/okf-gem/blob/main/resources/ci/github/README.md
---

# What it is

`resources/ci/github/okf.yml`, plus a README that explains the one line to
change. It runs `okf validate` and `okf lint` over a project's bundles from the
published Docker image, so a repository gets conformance checking with no Ruby
installed on the runner.

# The copy in `.github/` is byte-identical but for one line

This repository runs the recipe on itself, from `.github/workflows/okf.yml`. The
two files differ **only** in the `BUNDLES` line, and that is the arrangement:

* a recipe nobody runs rots, and a reader cannot tell;
* a recipe that has drifted from the copy its author runs is worse than none,
  because it looks tested.

Keeping the diff to one line is what makes "we run this" checkable rather than
claimed.

It is also the only place this repository's own conformance checking runs, which
makes it an instance of [a rule nothing runs](../design/nothing-runs-it.md)
settled the other way: the rule has a job, and the job is this file.

# The landmine it documents

The obvious way to write it — `container: ghcr.io/serradura/okf:latest` — does
not work, and fails in a way that reads as unrelated: `actions/checkout` is a
Node action, the image has no Node, and the checkout step dies before the
workflow reaches anything about OKF. So the recipe uses a plain `docker run`
with a bind mount, and says why in a comment rather than leaving the next person
to rediscover it.

The README also records what the verbs actually do at the exit-code level:
`validate` fails the job on an error, and `lint` is **advisory** — exit 0
whatever it finds, unless `--fail-on` is passed. That was checked by running it,
after the first draft claimed the opposite.
