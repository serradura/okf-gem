---
type: Component
title: The doors, and the load contract
description: Three ways in — the plugin verb, the Rack app, the library require — and the lazy-loading rule that keeps a bare `require "okf/mcp"` free of protocol machinery.
tags: [mcp, loading, cli, rack, plugin]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp.rb
---

# The files

| file | what it owns |
| ---- | ------------ |
| `lib/okf/mcp.rb` | the light entry: requires the served-set layer, defines `OKF::MCP` and `OKF::MCP::Error`, and the lazy `OKF::MCP.app` |
| `lib/okf/plugin.rb` | registers `okf mcp` with the kernel's command registry — the gem's only entry point, since there is no `exe/` |
| `lib/okf/mcp/cli.rb` | `OKF::MCP::CLI` — the argv shell: flag parsing, the boot announcement, stdio or `--http`, exit codes |
| `lib/okf/mcp/app.rb` | `OKF::MCP::App` and its `Scope` — transport construction for a Rack server, in exactly one place |
| `lib/okf/mcp/version.rb` | `OKF::MCP::VERSION` |

# The load contract

`require "okf/mcp"` loads **the registry seam and the backends only**. The MCP
SDK, WEBrick and the argv shell arrive on demand — from `okf/mcp/server`,
`okf/mcp/http`, `okf/mcp/cli`, or the lazy `OKF::MCP.app`, which requires
`mcp/app` inside the method rather than at the top of the file.

This is not tidiness. An application that embeds okf and happens to have
okf-mcp installed pays for neither the SDK nor WEBrick until something asks for
the protocol, and the kernel's plugin discovery `require`s `okf/plugin.rb` for
*every* unknown verb — so a heavy top-level require here would be a tax on
`okf help`.

`test/unit/loading_test.rb` pins it in a clean subprocess: after a bare
require, neither `::MCP` nor `::WEBrick` is defined. Adding a top-level
`require` to `lib/okf/mcp.rb` breaks that test, which is the intent.

# One place builds a transport

`App.build` and `App.transport` exist so that the `--http` path, the Rack path
and the tests cannot each compose the server differently. `CLI#prepare_http`
goes through the same seam. When a transport option is added, it is added
there, once — a second construction site is how two callers come to disagree
about `allowed_hosts`.

`App::Scope` is the Rack middleware that owns the transport's lifetime: it
answers `call`, and `close` tears the transport down. It is what makes
`run OKF::MCP.app` in a `config.ru` a complete answer with no rackup file of
this gem's own — the reader's server is the reader's dependency.
