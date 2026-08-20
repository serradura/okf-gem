---
okf_version: "0.2"
---

# okf-mcp knowledge bundle

**okf-mcp** is the MCP shell over the okf kernel (`@okf`): any MCP-capable agent
host can discover, orient in, search and read Open Knowledge Format bundles over
stdio or Streamable HTTP. This bundle is the gem's structural documentation —
what the code is, where each responsibility lives, and the rules a change has to
keep.

It is written to be read *before* opening `lib/`, so an agent about to add a
tool, a transport or a test does not re-derive the layering, and does not
rebuild something the kernel or this shell already answers. `AGENTS.md` beside
it is now only the contract and the commands; everything it used to restate
about the code lives here, once.

The **argument** for the server — why each tool exists, the bounded-output
doctrine, the posture — is [the tool set](design/the-tool-set.md). It used to
live in the repository's root bundle, back when that bundle was the kernel's and
described every surface; it came here when the root became the ecosystem's map.
What a *user* does with the gem stays the README's.

`structure/` is pinned: `test/unit/bundle_catalog_test.rb` fails when a file
under `lib/` is named by no concept, or when a concept names a file that is
gone. The tree is the truth and this bundle is the claim, so the two cannot
drift quietly.

* [Overview](overview.md) - The gem at a glance: the one rule, the four layers, and what it deliberately is not.

# Areas

* [Structure](structure/) - Every file under `lib/`, grouped by the layer that owns it: the doors, the served set, the protocol definition, and the HTTP bridge.
* [Capabilities](capabilities/) - The catalog: fourteen tools, the resources and prompts, and the three transports — what each answers, and what implements it.
* [Design](design/) - The rules a change has to keep: the inherited floor, the two dependencies, kernel-first, and the single entry point.
* [Testing](testing/) - How this gem is tested and how to add to it: what each layer proves, and the walk a new tool owes.
