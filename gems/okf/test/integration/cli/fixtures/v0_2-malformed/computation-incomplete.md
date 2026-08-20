---
type: Attested Computation
title: Computation Incomplete
description: §10.2 makes runtime REQUIRED for this type, and shapes executor and attester.
parameters:
  - name: year
    type: integer
  - type: string
  - just a string
executor: references/skills/run-on-bq.md
attester:
  language: python
---

# Overview

The type declares a sanctioned computation and then withholds what a consumer
needs to run one: no `runtime`, an `executor` that is a path rather than the
mapping §10.2 defines, an `attester` with no `resource`, and parameters that
are unnamed or not mappings at all.
