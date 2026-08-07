---
okf_version: "0.1"
---

# Hollow

A bundle whose `root/` directory carries an `index.md` and no concepts — the
shape that tells the two "does this bundle have a `root` directory?" answers
apart. The concept views read the *catalog*, which knows only directories that
hold concepts; `dirs` and `index` read the directory map, which counts an
`index.md` too. Both must give the same answer, or `--dir root` means one thing
to `catalog` and another to `dirs` in the very same bundle.

* [Charter](charter.md) - the only concept here
* [Root](root/index.md) - a directory with a map and nothing under it
