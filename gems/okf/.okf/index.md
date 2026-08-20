---
okf_version: "0.2"
---

# okf knowledge bundle

Everything about **okf**, the kernel of this ecosystem: what it does, how the
code is arranged, why each rule is a rule, and how a change is proven. It is
written to be read *before* opening `lib/`, so an agent about to add a verb, a
check or a search engine does not re-derive the layering and does not rebuild
something the model already answers.

`AGENTS.md` beside this bundle is the gem's maintainer guide. It keeps the
contract, the commands and the release steps, and routes here for everything
else; the repository root's guide is the ecosystem's and states no contract of
this gem's at all.

`structure/` is pinned: `test/unit/bundle_catalog_test.rb` fails when a file
under `lib/` is named by no concept, when a concept names a file that is gone,
or when the verb table in [cli](cli.md) disagrees with `OKF::CLI.builtins`. The
code is the truth and this bundle is the claim, so the two cannot drift quietly.

One thing is deliberately elsewhere. The **format** — what a citation is, what
§5 declares, what a bundle must contain — is the repository's own bundle
(`@okf-eco`), because the skill, the plugin, the three sibling gems and any future
non-Ruby implementation all speak it, and a reader asking about §5.1 is not
asking about a Ruby gem. A concept cannot link out of its own bundle, so
references to it name it in prose: `@okf-eco format/frontmatter`.

* [Overview](overview.md) - The gem at a glance: the seven capabilities and the design ethos behind them.
* [Command line](cli.md) - The `okf` executable — the one layer that parses argv, prints, and exits.
* [Bundle registry](registry.md) - The list of bundles a machine or a project knows, addressable as `@slug`.

# Areas

* [Structure](structure/) - Every file under `lib/`, grouped by the layer that owns it — pinned to the tree by a test.
* [The model](model/) - The pure in-memory data structures: concept, bundle, graph, skeleton.
* [Capabilities](capabilities/) - The things the gem does: validate, lint, search, serve, render, the library, the skill.
* [Design](design/) - The enforced boundaries that keep the gem light and honest.
* [Testing](testing/) - How a change is proven, and the walk a new verb owes.
