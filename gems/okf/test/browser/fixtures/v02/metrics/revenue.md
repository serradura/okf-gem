---
type: Attested Computation
title: Revenue
description: Net revenue by month, from captured invoices.
tags: [core]
status: stable
stale_after: 2099-12-31
runtime: bigquery
generated:
  by: human:maintainer
  at: 2026-06-04T00:00:00Z
executor:
  resource: references/skills/run-on-bq.md
  receipt: [ job_id ]
---

Computed from what [billing](../services/billing.md) captured.

# Computation

```sql
SELECT 1
```
