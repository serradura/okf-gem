---
type: BigQuery Table
title: Orders
description: One row per completed customer order.
resource: https://console.cloud.google.com/bigquery?t=orders
tags: [sales, orders]
status: stable
generated:
  by: human:maintainer
  at: 2026-05-28T09:15:00Z
verified:
  - by: process:nightly-schema-check
    at: 2026-06-26T02:00:00Z
  - by: human:maintainer
    at: 2026-06-27T11:00:00Z
usage_window:
  from: 2026-06-01
  to: 2026-06-30
sources:
  - id: bq-docs
    title: BigQuery documentation
    resource: https://cloud.google.com/bigquery
    last_modified: 2026-04-02
    usage_count: 4210
  - id: ingestion-runbook
    title: The ingestion runbook
    resource: https://example.com/runbooks/ingestion
    last_modified: 2026-05-11
---

# Schema

One row per completed order, keyed by `order_id`, partitioned by `order_date`.
Joined with [customers](/tables/customers.md) on `customer_id`.

Cancelled orders never land here — the ingestion job filters them upstream[^ingestion-runbook],
and the partitioning follows [the warehouse's own guidance](https://cloud.google.com/bigquery)[^bq-docs].
