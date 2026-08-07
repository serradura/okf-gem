---
type: Runbook
title: Billing restart
description: How to restart the billing service without dropping charges.
tags: [payments, oncall]
timestamp: 2026-06-25T08:00:00Z
status: active
---

1. Pause the charge queue and wait for in-flight invoices to settle.
2. Restart the [billing service](/services/billing.md).
3. Resume the queue and verify the ledger caught up.
