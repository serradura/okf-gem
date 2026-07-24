---
type: Charter
title: Charter
description: Why the checkout platform exists and what it promises.
tags: [core]
timestamp: 2026-06-01T00:00:00Z
---

The platform takes a cart and turns it into a paid order. Everything else —
the [gateway](services/gateway.md) that fronts it, the
[billing](services/billing.md) service that charges for it, the
[orders](datasets/orders.md) it writes — exists to serve that one sentence.

This concept sits at the bundle root on purpose: it is what makes the graph's
area filter show a `(root)` group, which no nested concept can produce.
