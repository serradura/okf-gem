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
---

# Schema

Joined with [customers](/tables/customers.md) on `customer_id`.
Part of the [sales dataset](/datasets/sales.md).
