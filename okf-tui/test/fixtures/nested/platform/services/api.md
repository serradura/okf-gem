---
type: Service
title: API
description: The public HTTP edge, two directories deep on purpose.
tags: [platform, service, edge]
timestamp: 2026-08-10
---

# Responsibilities

Accepts requests, hands the slow ones to the [worker](worker.md), and reads
through to the [warehouse](/platform/data/warehouse.md). Terms are defined in
[the vocabulary](/vocabulary/terms.md).
