---
type: Dataset
title: Orders
description: One row per order, written at capture time and never updated.
resource: https://example.test/datasets/orders
tags: [sales, core]
timestamp: 2026-06-04T00:00:00Z
---

Append-only. [Billing](/services/billing.md) is the only writer; everything
else reads.

Joins to [customers](customers.md) on `customer_id`.

```mermaid
graph LR
  Cart --> Gateway --> Billing --> Orders
```
