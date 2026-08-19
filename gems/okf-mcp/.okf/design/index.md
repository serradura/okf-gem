# Design

The rules a change has to keep. `AGENTS.md` states them as a contract in a
handful of lines; this is where each one's argument lives, so that a rule
questioned is a rule you can re-read rather than re-derive.

* [The inherited Ruby floor](ruby-floor.md) - 2.7, the `mcp` SDK's, not okf's 2.4 — and what that admits and forbids.
* [Two runtime dependencies](runtime-dependencies.md) - Exactly `mcp` and `okf`, with floors that track what the suite proves.
* [Kernel-first](kernel-first.md) - This shell restates nothing the kernel can answer, which is what stops the CLI and MCP answers drifting apart.
* [One entry point](one-entry-point.md) - `okf mcp` through the plugin seam, and why the executable was removed before the first release.
