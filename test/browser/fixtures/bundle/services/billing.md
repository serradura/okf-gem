---
type: Service
title: Billing
description: Issues invoices and captures payment against an order.
resource: https://example.test/services/billing
tags: [core]
timestamp: 2026-06-03T00:00:00Z
---

Billing is called by the [gateway](gateway.md) once a cart is confirmed. It
writes to [orders](/datasets/orders.md) and reads
[customers](/datasets/customers.md) for the billing address.

The datastore behind it is Postgres, for the reasons recorded in
[ADR 001](/decisions/adr-001-postgres.md).
