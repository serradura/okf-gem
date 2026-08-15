---
type: Service
title: Search
description: Full-text search over the product catalog.
tags: [discovery]
timestamp: 2026-06-18T14:00:00Z
status: active
verified:
  - by: human:sre
    at: 2026-06-20T09:00:00Z
---

Search indexes the product catalog nightly and serves ranked queries
with snippets. It knows nothing about invoices or payments.
