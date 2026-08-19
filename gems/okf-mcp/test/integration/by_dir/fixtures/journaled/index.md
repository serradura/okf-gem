---
okf_version: "0.1"
---

# Journaled

A bundle for the two directory kinds the served set and the `dirs` view must
agree about: `archive/` holds only a scoped `log.md` (a real directory — the
`log` tool reads it), and `drafts/` holds only a file the reader cannot parse
(not a directory the bundle can answer about — `dirs` has never listed it).

* [Charter](charter.md) - the only concept here
