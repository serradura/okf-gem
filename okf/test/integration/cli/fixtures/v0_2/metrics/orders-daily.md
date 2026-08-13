---
type: Attested Computation
title: Daily Orders
description: Completed order counts by day, for the operations dashboard.
tags: [sales, orders]
status: stable
runtime: bigquery
computation: references/computations/orders-daily.sql
generated:
  by: human:maintainer
  at: 2026-06-04T14:20:00Z
executor:
  resource: references/skills/run-on-bigquery.md
  receipt: [ job_id, row_count ]
sources:
  - title: The operations dashboard brief
    resource: https://example.com/briefs/ops-dashboard
---

# Overview

Counts completed orders per day from [orders](/tables/orders.md). The
computation is a file rather than a fence, which is the other shape §10.3
permits — the two exist side by side here on purpose.
