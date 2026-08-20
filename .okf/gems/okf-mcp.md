---
type: Component
title: okf-mcp — the MCP shell
description: A Model Context Protocol server over OKF bundles, so any MCP-capable agent host can discover, orient in, search and read them without a shell.
resource: gems/okf-mcp
tags: [gem, mcp, agent, protocol]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: gems/okf-mcp
    resource: https://github.com/serradura/okf/tree/main/gems/okf-mcp
  - title: gems/okf-mcp/README.md
    resource: https://github.com/serradura/okf/blob/main/gems/okf-mcp/README.md
---

# What it is

`okf-mcp` on RubyGems, at `gems/okf-mcp/`. It exposes the kernel's capabilities
as MCP tools, resources and prompts over stdio, Streamable HTTP, or as a Rack
app. An agent host that speaks MCP reads these bundles through it with no
terminal in the loop.

# What holds it in shape

| | |
|---|---|
| Ruby floor | **2.7** — the `mcp` SDK's, inherited rather than okf's |
| Runtime dependencies | exactly `mcp` and `okf`; rack and webrick arrive through okf and are never named |
| Entry point | no executable — `okf mcp` through the kernel's plugin seam |
| Posture | every tool is a read-only lens, every list answer carries a true `total`, and nothing truncates silently |

# The floor is the interesting part

It is the one gem that does not sit on 2.4, and the difference is inherited, not
chosen: a sibling's floor is its own. The repository runs one CI job per gem
rather than a gem axis on one matrix precisely because the floors diverge — see
[the monorepo layout](../decisions/monorepo-layout.md).

# Where its knowledge lives

`@okf-mcp` — `gems/okf-mcp/.okf/`, which ships inside the gem, so an installed
copy carries a real bundle for a host to read through the very tools it serves.
Its `structure/` area is pinned to the tree, and its `capabilities/tools.md` is
pinned to the tools `server.rb` actually defines.
