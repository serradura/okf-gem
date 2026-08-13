---
type: Service
title: Gateway
description: Terminates TLS and routes to the services behind it.
tags: [core]
status: stable
generated:
  by: human:maintainer
  at: 2026-06-02T00:00:00Z
verified:
  - by: human:reviewer
    at: 2026-06-20T00:00:00Z
sources:
  - id: edge-runbook
    title: The edge escalation runbook
    resource: https://example.test/runbooks/edge
---

The gateway calls [billing](billing.md) once a cart is confirmed, following the
runbook[^edge-runbook].
