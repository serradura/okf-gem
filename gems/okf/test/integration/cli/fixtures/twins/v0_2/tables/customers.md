---
type: BigQuery Table
title: Customers
description: One row per customer, current state only.
resource: https://console.cloud.google.com/bigquery?t=customers
tags: [sales, customers]
generated:
  by: human:maintainer
  at: 2026-05-20
sources:
  - title: The customer data policy
    resource: https://example.com/policies/customer-data
  - resource: https://example.com/policies/retention-schedule
---

# Schema

Current state only — there is no history table, so a customer's earlier address
is not recoverable here. Referenced by [orders](/tables/orders.md) through
`customer_id`.
