---
type: Overview
title: okf-mcp at a glance
description: Four layers between an MCP frame and the okf kernel — the doors, the served set, the server definition, the transports — and the one rule that decides every question about them.
tags: [mcp, overview, architecture]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
---

# The one rule

**This shell restates nothing the kernel can answer** —
[kernel-first](design/kernel-first.md), the rule that decides the rest. Every
tool is a library call into `okf`; logic a tool needs lands in the kernel and is read from there.
That is what keeps the CLI's answer and the MCP answer from drifting apart, and
it is the first question to ask of any change here: *could the kernel answer
this?* If it could, it should, and this gem calls it.

The consequence is that okf-mcp is small for what it does.
[Fourteen tools](capabilities/tools.md) over a 3,000-line `lib/`, most of which is schema, bounded-output arithmetic and the
HTTP bridge — almost none of it analysis.

# Four layers

```
  an MCP host
      │
      │  stdio, Streamable HTTP, or any Rack 3 server
      ▼
  transports      cli.rb · http.rb · app.rb
      │
      ▼
  definition      server.rb · output_schemas.rb · resources.rb · prompts/
      │           fourteen tools, two prompts, one declared shape per tool
      ▼
  served set      registry.rb · filters.rb · backend.rb · memory_backend.rb
      │           which bundles exist, and the cache in front of them
      ▼
  the okf kernel  Bundle, Folder, Search, Validator, Linter — all the analysis
```

Read them in that order and each one only depends on the layer below it. The
[structure](structure/) area is one concept per layer, and it names every file —
start at [the doors](structure/doors.md).

# What it is not

It is not a second implementation of okf, and it is not a writer: every tool is
a read-only lens, declared as one on the wire. It is also not a program you
start on its own — there is no `exe/`; `okf mcp` through the kernel's plugin
seam is the [single entry point](design/one-entry-point.md).

The argument for *why* the tool set is what it is — why fourteen and not
thirty, what `total` means, why domain failures carry the kernel's own
sentences — is the root bundle's `capabilities/mcp-server.md`, not restated
here. This bundle is about the code that serves it.
