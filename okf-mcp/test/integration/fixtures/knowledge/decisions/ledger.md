---
type: Decision
title: Ledger
description: Billing writes to an append-only ledger instead of mutating balances.
tags: [payments]
timestamp: 2026-07-01T10:00:00Z
status: accepted
---

Mutating balances in place made reconciliation impossible after partial
failures. The append-only ledger gives every invoice a full audit trail,
at the cost of a nightly compaction job in [billing](/services/billing.md).
