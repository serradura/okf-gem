---
type: Component
title: okf-principles
description: A skill about how to structure instructions for an agent at all — canonical here, belonging to no gem, and the reason `skills/` is not simply a generated directory.
resource: skills/okf-principles
tags: [skill, agent, principles, canonical]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: skills/okf-principles
    resource: https://github.com/serradura/okf-gem/tree/main/skills/okf-principles
---

# What it is

Six files under `skills/okf-principles/`, and **this is the canonical copy** —
there is no tree inside a gem that it is generated from.

That is because of what it documents: a way of *structuring instructions*, not
okf's code. No gem ships it, no gem could sensibly own it, and it would be just
as useful to someone who never installs okf.

# Why it matters to this repository's shape

It is the counter-example that keeps [`skills/`](okf-skill.md) honest. If both skills were
generated copies, `skills/` would be build output and the rule would be simple:
never edit anything here.

It is not build output. One entry is generated and must never be edited; one is
canonical and can only be edited here. Anyone touching `skills/` has to know
which is which — which is why the two have separate concepts rather than one.
