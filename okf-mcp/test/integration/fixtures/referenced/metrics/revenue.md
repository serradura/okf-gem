---
type: Attested Computation
title: Revenue
description: Cites an attester, run instructions, and one bare path that misses.
runtime: bigquery
generated:
  by: human:maintainer
  at: 2026-06-02T10:00:00Z
executor:
  resource: /references/skills/run-on-bq.md
  receipt: [ job_id ]
attester:
  resource: /references/attesters/revenue.py
sources:
  - title: The scratch notes
    resource: references/notes/scratch.txt
---

# Overview

The sources entry spells its path bare from `metrics/`, so §6.2 resolves it to
`metrics/references/notes/scratch.txt` — nothing — while the leading-slash
spelling would have hit.

# Computation

```sql
SELECT 1
```
