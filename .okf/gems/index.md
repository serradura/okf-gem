# The gems

Four gems, one per directory under `gems/`, and the arrangement is deliberate:
**one kernel and three shells.** okf owns the format, the model and every
judgement about a bundle; the other three are surfaces over the answers it
computes, and none of them recomputes one.

That is what keeps four programs from disagreeing about how big a bundle is or
whether it lints clean — a failure this repository has actually had, when a
renamed kernel field left a surface reporting a wrong number that looked right.

Each gem carries its own knowledge bundle beside its code, addressed by slug.
This bundle points at them; it does not restate them.

* [okf](okf.md) - The kernel: the format, the model, the analysers, the CLI, the server, the skill.
* [okf-mcp](okf-mcp.md) - The MCP shell: those capabilities as tools a host can call.
* [okf-tui](okf-tui.md) - The terminal UI: six views over one bundle or many.
* [okf-pro](okf-pro.md) - The enforcement layer: a bundle an agent is held to.
