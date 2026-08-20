---
type: Service
title: Gateway
description: The public edge that terminates TLS and routes to everything else.
resource: https://example.test/services/gateway
tags: [edge, public, core]
timestamp: 2026-06-02T00:00:00Z
---

Every request enters here. The gateway authenticates the caller, applies the
rate limit, and forwards to [billing](billing.md) for anything that moves
money.

Deploys go through the [deploy runbook](/runbooks/deploy.md); when one goes
wrong, the [rollback runbook](/runbooks/rollback.md) is the way back.
