---
type: Runbook
title: Sweep
description: The nightly job that collects entries, confirmed by a process.
tags: [records]
status: stable
stale_after: 2026-12-31
generated:
  by: process:collector
  at: 2026-08-12T02:00:00Z
verified:
  by: process:collector
  at: 2026-08-12T02:05:00Z
sources:
  - resource: https://example.test/sweep-runbook
---

# Sweep

Writes the [entries](records/entries.md) the [ledger](ledger.md) reads.
