---
okf_version: "0.1"
---

# okf-gem capabilities

What the `okf` gem does over an Open Knowledge Format v0.1 bundle: read it,
search it, validate it, lint it, serve it, render it, and let an agent author it.
Start here.

* [Overview](overview.md) - the gem at a glance: the seven capabilities and the design ethos behind them.
* [Command line](cli.md) - the `okf` executable — the one layer that parses argv, prints, and exits.
* [Bundle registry](registry.md) - the per-user list of bundles under `$OKF_HOME` that a bare `okf server` hosts.

# Areas

* [The format](format/) - what OKF v0.1 is — the Markdown + YAML frontmatter the gem operates on.
* [The model](model/) - the pure in-memory data structures: concept, bundle, graph.
* [Capabilities](capabilities/) - the seven things the gem does: validate, lint, search, serve, render, the library, the skill.
* [Design constraints](design/) - the enforced boundaries that keep the gem light and honest.
