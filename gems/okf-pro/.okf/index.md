---
okf_version: "0.2"
---

# okf-pro knowledge bundle

The non-obvious knowledge behind **okf-pro** — the gem that turns an
[okf](@okf) bundle into a working memory an agent is held to. The `README`
documents the verbs and the scaffold, and `AGENTS.md` carries the contracts a
change has to keep; this bundle deliberately restates neither.

It captures two things. The first is the argument the gem serves — three laws,
the failures each one closes, and the limit each one admits — because the rules
are borrowed and reasoned rather than obvious, and a rule whose reasoning is
lost gets re-argued from scratch every time someone questions it.

The second is the thing this gem is unusual for: **every defect here fails
in the direction of silence.** A gate that cannot run, a check that was skipped,
a shim on PATH, a status code the protocol reads as "proceed" — each of them
produces an unchecked bundle that is indistinguishable, from the outside, from a
clean one. So the knowledge worth recording is not what the checks assert; it is
where the machinery around them can stop asserting anything without saying so.

# Areas

* [Design](design/) - Why the rules exist: three pillars, three laws, the eight failures they close, and what was borrowed.
* [Contract](contract/) - Fail closed, fail loud, never fail silent — and the exit codes that make it true.
* [Seam](seam/) - The plugin entry point, the three ways it fails open, and the wrapper that closes them.
* [Scaffold](scaffold/) - What `setup` writes, who owns each file afterwards, and why no date ships.
* [Trust](trust/) - The v0.2 read-owed rule, and the four call sites that must agree about it.
* [Testing](testing/) - Drills over unit tests, and the fixture that is a client of the code it tests.
