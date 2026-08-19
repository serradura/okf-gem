---
type: BigQuery Table
title: Orders
description: One row per completed customer order.
resource: https://console.cloud.google.com/bigquery?t=orders
tags: [sales, orders]
timestamp: 2026-05-28
---

# Schema

One row per completed order, keyed by `order_id`. Joined with
[customers](/tables/customers.md) on `customer_id`. Cancelled orders never land
here; they are filtered upstream by the ingestion job.

# Citations

[1] [BigQuery docs](https://cloud.google.com/bigquery)
[2] [The ingestion runbook](https://example.com/runbooks/ingestion)
