---
type: Decision
title: "ADR 001: Postgres"
description: Why the platform stores orders in Postgres rather than a document store.
tags: [core]
timestamp: 2026-06-08T00:00:00Z
---

[Billing](/services/billing.md) needs a transaction across the invoice and the
[orders](/datasets/orders.md) row. That is the whole argument: one write that
either lands entirely or not at all.

A document store would have meant reconciling the two afterwards, which is a
job nobody would own.
