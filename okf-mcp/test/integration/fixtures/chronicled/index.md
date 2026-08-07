---
okf_version: "0.1"
---

# Chronicled

A bundle whose history is long enough to need bounding — six dated entries in
the root log, two in `ops/`. Every other fixture's log is shorter than any
sensible default, so the truncation branch was unreachable from all of them.

## Concepts

* [Ledger](ledger.md) — the one concept; the log is what this fixture is for.

## Directories

* [ops](ops/) — a second log file, so the bound is proven per file.
