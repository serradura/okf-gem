---
type: Attested Computation
title: <What the computation answers, e.g. Revenue for fiscal year>
description: <Single sentence: what this computes and per whose definition.>
tags: [<tag>]
runtime: <REQUIRED — what runs it and what parameters mean: bigquery, dbt, python, …>
parameters:
  - { name: <name>, type: <type>, required: true }
executor:
  resource: <path to run instructions, e.g. references/skills/run-on-bq.md>
  receipt: [<field>, <field>]
attester:
  resource: <path to the deterministic check, e.g. references/attesters/check.py>
generated: { by: <actor per §7>, at: <ISO 8601> }
sources:
  - id: <stable-key>
    title: <the definition this computation implements>
    resource: <url or path>
---

# Computation

<The sanctioned computation, in one fenced block — OR set `computation: <path>`
in the frontmatter instead and omit this section entirely (§10.3: a path is
used *instead of* the fence; providing both leaves a consumer two candidate
computations and no rule for which was sanctioned).>

```<language>
<the computation>
```

<Prose around it may cite sources per claim.[^<stable-key>]>

<!-- rule:okf-computation-untouched -->
<!-- §10.3, v0.2's only new MUST NOT: an agent MAY bind values for the declared
     `parameters` and MUST NOT author or edit the computation itself. The whole
     point of the type is that the computation is sanctioned — reviewed by a
     person — and an improvised or "fixed" query silently loses that status.
     If the computation is wrong, say so to a human; do not repair it. -->
