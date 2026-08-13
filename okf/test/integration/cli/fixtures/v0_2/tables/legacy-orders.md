---
type: BigQuery Table
title: Legacy Orders
description: The pre-migration order table, retained for reconciliation only.
resource: https://console.cloud.google.com/bigquery?t=legacy_orders
tags: [sales, orders, legacy]
status: deprecated
stale_after: 2099-12-31
generated:
  by: human:maintainer
  at: 2026-01-09T08:00:00Z
sources:
  - title: The migration plan
    resource: https://example.com/plans/order-migration
---

# Schema

Frozen at the migration cutover and never written to again. Read it only to
reconcile totals against [orders](/tables/orders.md); everything current lives
there.

The far-future `stale_after` is deliberate: this fixture must never expire on
its own, or the suite would start failing on a calendar rather than a change.
