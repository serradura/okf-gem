---
okf_version: "0.1"
---

# okf-gem capabilities

What the `okf` gem does over an Open Knowledge Format v0.1 bundle: read it,
validate it, lint it, serve it, and let an agent author it. Start here.

* [Overview](overview.md) - the gem at a glance: the five capabilities and the design ethos behind them.
* [Command line](cli.md) - the `okf` executable — the one layer that parses argv, prints, and exits.

# Areas

* [The format](format/) - what OKF v0.1 is — the Markdown + YAML frontmatter the gem operates on.
* [The model](model/) - the pure in-memory data structures: concept, bundle, graph.
* [Capabilities](capabilities/) - the five things the gem does: validate, lint, serve, the library, the skill.
* [Design constraints](design/) - the enforced boundaries that keep the gem light and honest.
