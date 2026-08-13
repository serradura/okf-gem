---
type: BigQuery Table
title: Customers
description: One row per customer, current state only.
resource: https://console.cloud.google.com/bigquery?t=customers
tags: [sales, customers]
status: draft
generated:
  by: reference_agent/gemini-2.5-pro
  at: 2026-05-20T16:40:00Z
verified:
  by: process:nightly-schema-check
  at: 2026-06-26T02:00:00Z
sources:
  - id: customer-policy
    title: The customer data policy
    resource: https://example.com/policies/customer-data
    last_modified: 2026-03-30
---

# Schema

Current state only — there is no history table, so a customer's earlier address
is not recoverable here. Referenced by [orders](/tables/orders.md) through
`customer_id`.

Retention follows the data policy[^customer-policy], which is why deleted
customers disappear rather than tombstoning.
