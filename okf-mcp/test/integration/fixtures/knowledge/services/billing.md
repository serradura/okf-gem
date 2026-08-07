---
type: Service
title: Billing
description: Charges customers and issues invoices on a monthly cycle.
tags: [payments, core]
timestamp: 2026-06-20T09:00:00Z
status: active
---

Billing charges every active subscription and issues invoices. Failed
charges retry with exponential backoff before an invoice is marked
delinquent. All monetary movements land in the
[append-only ledger](/decisions/ledger.md); restarts follow the
[billing restart runbook](/runbooks/billing-restart.md).
