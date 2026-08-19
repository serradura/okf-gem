---
okf_version: "0.2"
---

# okf-pro knowledge bundle

The knowledge behind **okf-pro** — the gem that turns an [okf](@okf) bundle
into a working memory an agent is held to. It is written to be read *before*
opening `lib/`, so an agent about to add a check, a verb or a test does not
re-derive the layering and does not rebuild something this gem already answers.

`AGENTS.md` beside it carries the contract, the constraints and the commands,
and routes here for everything else; the `README` is the adopter's. What used
to be a hand-maintained Map of `lib/**` in `AGENTS.md` now lives in
[Structure](structure/), pinned by `test/unit/bundle_catalog_test.rb` — the
code is the truth and this bundle is the claim, so the two cannot drift
quietly.

It also captures the argument the gem serves — three laws, the failures each
one closes, and the limit each one admits — because the rules are borrowed and
reasoned rather than obvious, and a rule whose reasoning is lost gets re-argued
from scratch every time someone questions it.

And the thing this gem is unusual for: **every defect here fails in the
direction of silence.** A gate that cannot run, a check that was skipped, a shim
on `PATH`, a status code the protocol reads as "proceed" — each of them produces
an unchecked bundle that is indistinguishable, from the outside, from a clean
one. So the knowledge worth recording is not what the checks assert; it is where
the machinery around them can stop asserting anything without saying so.

# Areas

* [Structure](structure/) - Every file under `lib/`, grouped by the layer that owns it: the doors, the readers, the gates, the guards, the writers, the scaffold, the recorder.
* [Capabilities](capabilities/) - The catalogue: sixteen verbs and nine checks — what each answers, before you write a seventeenth.
* [Design](design/) - Why the rules exist: three pillars, three laws, the eight failures they close, and what was borrowed.
* [Contract](contract/) - Fail closed, fail loud, never fail silent — and the exit codes that make it true.
* [Seam](seam/) - The plugin entry point, the three ways it fails open, and the wrapper that closes them.
* [Scaffold](scaffold/) - What `setup` writes, who owns each file afterwards, and why no date ships.
* [Trust](trust/) - The v0.2 read-owed rule, and the four call sites that must agree about it.
* [Testing](testing/) - Drills over unit tests, and the fixture that is a client of the code it tests.
