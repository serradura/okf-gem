---
type: BigQuery Table
title: Orders
description: One row per completed customer order.
resource: https://console.cloud.google.com/bigquery?t=orders
tags: [sales, orders]
generated:
  by: human:maintainer
  at: 2026-05-28
sources:
  - title: BigQuery docs
    resource: https://cloud.google.com/bigquery
  - title: The ingestion runbook
    resource: https://example.com/runbooks/ingestion
---

# Schema

One row per completed order, keyed by `order_id`. Joined with
[customers](/tables/customers.md) on `customer_id`. Cancelled orders never land
here; they are filtered upstream by the ingestion job.
