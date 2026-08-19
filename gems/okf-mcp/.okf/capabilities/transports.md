---
type: Capability
title: Three transports, one definition
description: stdio by default, Streamable HTTP behind `--http`, and any Rack 3 server through `OKF::MCP.app` — all three built at one seam so they cannot compose the server differently.
tags: [mcp, transports, stdio, http, rack]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/app.rb
---

# The three

| transport | how | who owns it |
| --------- | --- | ----------- |
| stdio | the default for `okf mcp` | `CLI#serve_stdio` |
| Streamable HTTP | `okf mcp --http` — the WEBrick bridge, stateless JSON mode | [`HTTP`](../structure/http-bridge.md) |
| any Rack 3 server | `run OKF::MCP.app` in a `config.ru` | [`App`](../structure/doors.md) |

stdio is the default because it is what an agent host launches; nothing has to
be bound, and there is no port to collide.

# One construction site

All three reach the transport through `App.build` / `App.transport`. This is
worth protecting: the moment two callers construct their own, they begin to
disagree about `allowed_hosts`, `allowed_origins` or the engine, and the
disagreement shows up as a security difference between `--http` and a Rack
deployment rather than as a test failure.

`test/integration/http_harness.rb` is the same idea one layer up — the three
HTTP test files share it so they cannot drift in how they compose the bridge.

# No rackup file of its own

This gem ships no `config.ru`. The reader's server is the reader's dependency:
`OKF::MCP.app` is a complete Rack application, and naming a server here would
add a dependency to satisfy a convenience. The bridge behind `--http` uses
WEBrick, which arrives through okf rather than being named in this gemspec.
