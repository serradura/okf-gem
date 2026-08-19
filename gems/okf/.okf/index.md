---
okf_version: "0.2"
---

# okf knowledge bundle

**okf** is the kernel of this ecosystem: it reads, validates, lints and serves
Open Knowledge Format bundles, and the MCP shell, the TUI and the enforcement
layer are all readers of the answers it computes. This bundle is the gem's
structural documentation — what the code is, where each responsibility lives,
what it already answers, and how a change is proven.

It is written to be read *before* opening `lib/`, so an agent about to add a
verb, a check or a search engine does not re-derive the layering and does not
rebuild something the model already exposes.

`AGENTS.md` at the repository root is this gem's maintainer guide as well as the
monorepo's, and it keeps the hard constraints, the release process and the Git
rules; what it used to restate about the shape of `lib/**` and the shape of the
test suite lives here now, once.

`structure/` is pinned: `test/unit/bundle_catalog_test.rb` fails when a file
under `lib/` is named by no concept, when a concept names a file that is gone,
or when the verb catalogue and the command registry disagree. The code is the
truth and this bundle is the claim, so the two cannot drift quietly.

Two things are deliberately elsewhere. The **format** — what a citation is, what
§5 declares, what a bundle must contain — is the repository bundle's, because
the skill, the plugin and every future non-Ruby implementation speak it and a
reader asking about §5.1 is not asking about this gem. And what a *user* does
with okf is the README's.

* [Overview](overview.md) - The gem at a glance: one rule, four doors, and what it deliberately is not.

# Areas

* [Structure](structure/) - Every file under `lib/`, grouped by the layer that owns it: the format layer, the model, the analysers, search, the disk shell, the server, the CLI, the skill.
* [Capabilities](capabilities/) - The catalogue: seventeen verbs and eight subcommands, and what `require "okf"` gives an embedding application.
* [Testing](testing/) - Integration first, organised by the three ways a user names a bundle; how to read coverage, and the walk a new verb owes.
