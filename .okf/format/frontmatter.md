---
type: Format
title: Frontmatter (spec §4)
description: The YAML header on every concept, parsed through the gem's single, hardened YAML gateway.
resource: okf/lib/okf/markdown/frontmatter.rb
tags: [yaml]
timestamp: 2026-07-17T16:00:00Z
---

# Overview

Every [concept](../model/concept.md) opens with a YAML frontmatter block delimited
by `---` lines. `OKF::Markdown::Frontmatter` parses it and is the inverse of
`Concept#to_markdown`. The only **required** key is
[`type`](../format/okf-format.md); `title`, `description`, `resource`, `tags`, and
`timestamp` are recommended, and producers may add any other keys — consumers
preserve unknown keys and never reject a document for having them.

# The one YAML gateway

All YAML in the gem flows through this one class. That is a deliberate security
and portability boundary, not an accident of layering:

- it uses `safe_load` — permitting `Date`/`Time`, forbidding aliases — so a
  bundle can never execute arbitrary Ruby on load;
- it carries the Psych `<3.1` positional-argument shim, so the gem parses
  identically on the old Ruby versions the [2.4 floor](../design/ruby-floor.md)
  targets;
- `stringify_keys` lives here so the gem needs no ActiveSupport (see
  [runtime dependencies](../design/runtime-dependencies.md)).

The rule is enforced by convention: `YAML.safe_load` / `YAML.load` appear
**nowhere else** in the codebase.

# Citations

[1] [okf/lib/okf/markdown/frontmatter.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/markdown/frontmatter.rb) — the parser and the Psych shim.
[2] [SPEC.md §4](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/skill/reference/SPEC.md) — concept documents and frontmatter.
