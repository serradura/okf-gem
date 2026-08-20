---
type: Capability
title: Conformance validator (validate)
description: Implements the spec's §11 conformance definition exactly — three hard conditions, everything else a machine-readable warning.
resource: gems/okf/lib/okf/bundle/validator.rb
tags: [conformance, cli]
generated:
  by: human:maintainer
  at: 2026-08-13T12:00:00Z
sources:
  - title: gems/okf/lib/okf/bundle/validator.rb
    resource: https://github.com/serradura/okf/blob/main/gems/okf/lib/okf/bundle/validator.rb
---

# Overview

`okf validate` answers one question: *is this a legal OKF (`@okf-eco format/okf-format`)
bundle?* `OKF::Bundle::Validator` implements §11 exactly and is the **only**
capability that can fail a bundle — exit `1` on any hard error, `0` otherwise.

# The three hard conditions (errors)

| Rule | Condition |
|------|-----------|
| §11 cond. 1 | every non-reserved file can be **read** and has a parseable frontmatter (`@okf-eco format/frontmatter`) block |
| §11 cond. 2 | every such block has a **non-empty `type`** |
| §11 cond. 3 | every `index.md` / `log.md` present is well-formed (nested index has no frontmatter, root index carries only `okf_version`, log dates are real ISO calendar days — `2026-02-30` matches the shape and is refused) |

A file that will not **open** fails condition 1 too, not only one whose frontmatter will
not parse: the reader keeps it in [`bundle.unparseable`](../model/bundle.md) with
its errno rather than letting one locked file abort the read, and `validate`
reports it there — one unusable file counted as one, named with why.

# Everything else is a warning

The validator is **forbidden by §11** from rejecting a bundle for soft issues, so
these are warnings that never change conformance:

- missing recommended fields, non-list `tags`, an unparseable `timestamp`;
- the shape of every §5/§10 family — `generated` not a mapping or missing `by`,
  a non-integer `usage_count`, a `stale_after` that is not `YYYY-MM-DD`, a
  missing `runtime` on an Attested Computation — read off the raw keys, never
  the fallback-carrying accessors, so a pure v0.1 bundle validates silently;
- an `okf_version` the gem does not know (read best-effort under §12, compared
  after `to_s.strip` because an unquoted `0.2` is a Psych Float);
- **broken cross-links (`@okf-eco format/cross-links`)** (§6.1) — consumers MUST
  tolerate them.

Judging those is the [linter](linter.md)'s job, and keeping the two apart is a
[hard design contract](../design/core-shell-split.md). The
[writer](library-api.md) runs this validator *before* publishing, so a saved
bundle is never written non-conformant.

# Warnings are machine-readable

Every warning carries `check:` (a stable id) and `source:` — `:spec` when the
SPEC's own words state the rule, `:convention` for the shapes this gem asks for
beyond them (a tested constant pins the set). A consumer that wants only the
spec-normative warnings filters on `source` instead of string-matching
messages; errors keep their exact two-key `{ path, message }` shape.
