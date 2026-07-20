---
type: Runbook
title: Rollback
description: Undoing a release that has already taken traffic.
tags: [ops]
timestamp: 2026-06-07T00:00:00Z
---

The inverse of [deploy](deploy.md): [billing](/services/billing.md) goes back
first, then [gateway](/services/gateway.md).

[Orders](/datasets/orders.md) is append-only, so a rollback never has to undo
a write — that property is why the append-only shape was chosen.
