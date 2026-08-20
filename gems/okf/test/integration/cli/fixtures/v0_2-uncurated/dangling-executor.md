---
type: Attested Computation
title: Dangling Executor
description: Its executor names run instructions this bundle does not carry.
runtime: bigquery
generated:
  by: human:maintainer
  at: 2026-06-04T14:20:00Z
executor:
  resource: /references/skills/missing-runbook.md
  receipt: [ job_id ]
---

# Overview

The contract is complete in shape — a runtime, a receipt, and a computation
below — and points at run instructions that are not here, so no consumer can
follow it. Related: [both computation](both-computation.md).

# Computation

```sql
SELECT 1
```
