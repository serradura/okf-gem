---
okf_version: "0.2"
---

# The OKF ecosystem

The map of this repository: what is in it, what each part is for, and the
decisions that put them where they are. It is the **connection layer** — every
bucket below is a top-level name in the tree, and every item in a bucket has a
concept pointing at the thing itself.

This bundle is `@okf-eco`. It deliberately explains no gem: each of the four
carries its own bundle beside its code — `@okf`, `@okf-mcp`, `@okf-tui`,
`@okf-pro` — and this one points at them rather than restating them.
`okf search @all <term>` reaches all five at once.

The plain `@okf` belongs to the gem, not here. A reader who types it is almost
always asking about the kernel's code, and the ecosystem is the thing you arrive
at rather than the thing you look up.

* [Overview](overview.md) - One format, one kernel, three shells, three ways it leaves this repository.

# Areas

* [The gems](gems/) - The four packages: one kernel and three surfaces over it, with what holds each in shape.
* [The plugin](plugin/) - The Claude Code plugin, its curation hook, and the marketplace manifest that offers it.
* [The skills](skills/) - What an agent installs: one generated copy, and one skill that is canonical here.
* [The resources](resources/) - What someone copies out into a project of their own.
* [Decisions](decisions/) - The forks that could have gone otherwise, each with the argument that settled it.
* [Design](design/) - The structure the decisions are arranged against, and the rules that keep it.
* [The format](format/) - OKF v0.2 itself — the one thing all four gems, and any future non-Ruby implementation, speak.
