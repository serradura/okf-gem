---
type: Format
title: Open Knowledge Format v0.1
description: Portable knowledge as a directory of Markdown files with YAML frontmatter that humans and agents both read.
resource: lib/okf/skill/reference/SPEC.md
tags: [okf, conformance]
timestamp: 2026-07-17T16:00:00Z
---

# Overview

OKF is a bundle: a directory of UTF-8 Markdown files. Each non-reserved file is
one **concept** with two parts — a [YAML frontmatter block](frontmatter.md) and a
Markdown body. Knowledge is the files; the graph is
[how they link](cross-links.md). There is no schema registry, no runtime, no
SDK — the format is minimal on purpose, and the gem is what gives it leverage.

# Reserved files

Two filenames are reserved and are never concepts:

| File | Role | Constraint |
|------|------|------------|
| `index.md` | a directory listing for progressive disclosure | carries **no** frontmatter — except the bundle-root `index.md`, which may carry *only* `okf_version` |
| `log.md` | a dated change history, newest first | date headings are ISO `YYYY-MM-DD` |

# §9 conformance is narrow and tolerant

The spec makes only three conditions **hard**, and the
[validator](../capabilities/validator.md) fails a bundle on any of them:

1. **§9.1** — every non-reserved `.md` file has a parseable frontmatter block;
2. **§9.2** — every such block has a **non-empty `type`**;
3. **§9.3** — every reserved file present is well-formed.

Everything else is soft guidance a consumer MUST tolerate: missing optional
fields, unknown [`type`](../model/concept.md) values, and **broken cross-links**.
Judging those is the [linter](../capabilities/linter.md)'s job, held separate on
purpose.

# Citations

[1] [SPEC.md](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/reference/SPEC.md) — the OKF v0.1 specification, authored by Google Cloud Platform, redistributed under Apache 2.0.
