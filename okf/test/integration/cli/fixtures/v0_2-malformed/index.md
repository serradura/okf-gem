---
okf_version: "9.9"
---

# Shapes the validator warns about

Every file here is *conformant* — §11's three conditions all hold — and every
one carries a v0.2 family written in a shape the spec does not define. The
whole fixture must stay at exit 0: these are warnings, and a warning that
became an error would break §11.

* [Generated not a mapping](generated-not-a-mapping.md)
* [Generated missing by](generated-missing-by.md)
* [Generated unparseable at](generated-bad-at.md)
* [Verified not a list](verified-not-a-list.md)
* [Verified entries](verified-bad-entries.md)
* [Sources not a list](sources-not-a-list.md)
* [Sources entries](sources-bad-entries.md)
* [Usage window](usage-window-bad.md)
* [Status outside the three](status-unknown.md)
* [Stale after unparseable](stale-after-bad.md)
* [Usage window not a mapping](usage-window-not-a-mapping.md)
* [Parameters not a list](parameters-not-a-list.md)
* [Stale after with a time](stale-after-datetime.md)
* [Computation contract](computation-incomplete.md)
