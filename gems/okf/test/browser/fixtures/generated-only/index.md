---
okf_version: "0.2"
---

# A bundle mid-migration, nothing reviewed yet

Two concepts declare `generated:`, none declares `verified:`, and one is still
plain v0.1 — the ordinary state of a bundle the moment its migration lands, and
the arrangement the `v02` fixture cannot make, since two of its concepts are
verified on purpose.

* [Billing](billing.md) - the service, still under review
* [Gateway](gateway.md) - the edge, shipped
* [Legacy Ledger](legacy-ledger.md) - not migrated, so it claims no tier
