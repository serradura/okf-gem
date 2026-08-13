---
type: Attested Computation
title: Monthly Revenue
description: Net revenue by calendar month, from completed orders only.
tags: [sales, revenue]
status: stable
runtime: bigquery
generated:
  by: human:maintainer
  at: 2026-06-02T10:00:00Z
parameters:
  - name: year
    type: integer
    required: true
  - name: currency
    type: string
    required: false
executor:
  resource: references/skills/run-on-bigquery.md
  receipt: [ job_id, row_count, bytes_billed ]
attester:
  resource: references/attesters/revenue.py
sources:
  - id: orders-table
    title: The orders table
    resource: https://console.cloud.google.com/bigquery?t=orders
---

# Overview

Net revenue by month, computed from [orders](/tables/orders.md) with cancelled
rows already excluded upstream[^orders-table].

# Computation

```sql
SELECT DATE_TRUNC(order_date, MONTH) AS month, SUM(net_amount) AS revenue
FROM `sales.orders`
WHERE EXTRACT(YEAR FROM order_date) = @year
GROUP BY month
ORDER BY month
```
