---
type: Runbook
title: Deploy
description: How a release reaches production, and what to watch while it does.
tags: [ops]
timestamp: 2026-06-06T00:00:00Z
---

Ship [gateway](/services/gateway.md) first, then
[billing](/services/billing.md) — the reverse order breaks the contract
between them for as long as the window is open.

If the error rate moves, go to [rollback](rollback.md).
