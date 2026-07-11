---
type: Capability
title: Conformance validator (validate)
description: Implements the spec's §9 conformance definition exactly — three hard conditions, everything else a warning.
resource: lib/okf/bundle/validator.rb
tags: [validation, conformance, cli]
timestamp: 2026-07-11T12:00:00Z
---

# Overview

`okf validate` answers one question: *is this a legal [OKF](../format/okf-format.md)
bundle?* `OKF::Bundle::Validator` implements §9 exactly and is the **only**
capability that can fail a bundle — exit `1` on any hard error, `0` otherwise.

# The three hard conditions (errors)

| Rule | Condition |
|------|-----------|
| §9.1 | every non-reserved file has a parseable [frontmatter](../format/frontmatter.md) block |
| §9.2 | every such block has a **non-empty `type`** |
| §9.3 | every `index.md` / `log.md` present is well-formed (nested index has no frontmatter, root index carries only `okf_version`, log dates are ISO) |

# Everything else is a warning

The validator is **forbidden by §9** from rejecting a bundle for soft issues, so
these are warnings that never change conformance:

- missing recommended fields, non-list `tags`, an unparseable `timestamp`;
- **broken [cross-links](../format/cross-links.md)** (§5.3) — consumers MUST
  tolerate them.

Judging those is the [linter](linter.md)'s job, and keeping the two apart is a
[hard design contract](../design/core-shell-split.md). The
[writer](library-api.md) runs this validator *before* publishing, so a saved
bundle is never written non-conformant.

# Citations

[1] [lib/okf/bundle/validator.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/bundle/validator.rb) — the §9 implementation.
