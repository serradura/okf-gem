---
type: Runbook
title: Rollback
description: Undoing a release that has already taken traffic.
tags: [ops]
timestamp: 2026-06-07T00:00:00Z
---

The inverse of [deploy](deploy.md): [billing](/services/billing.md) goes back
first, then [gateway](/services/gateway.md).

[Orders](/datasets/orders.md) is append-only, so a rollback never has to undo
a write — that property is why the append-only shape was chosen.

## See also

The non-concept link kinds the inspector has to resolve — an authored map, the
history, a synthesized directory, and one target that is none of them:

* This bundle's [root map](/index.md) and its [update log](/log.md).
* The [datasets folder](/datasets/), which carries no index.md of its own.
* [A note that is not in this bundle](nowhere/) — nothing to open.

# Citations

[1] [The OKF format on the web](https://okfgem.com) — an external link, which
the inspector opens in a new tab rather than resolving in place.
