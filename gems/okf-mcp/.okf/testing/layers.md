---
type: Constraint
title: What each test layer proves
description: Integration-first over real JSON-RPC frames, with process-spawning confined to the two files that prove the process — plus the wire-reading rules the SSE tests cannot be written without.
tags: [testing, integration, http, sse]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: test/integration
---

# The layers

| layer | proves | files |
| ----- | ------ | ----- |
| tool integration | a tool's real answer, driven as JSON-RPC through `handle_json` | `test/integration/{by_dir,by_registry,across_bundles}/` |
| protocol surface | capabilities, output schemas, resources, completions, prompts | `capabilities_test.rb`, `output_schema_test.rb`, `resources_test.rb`, `completions_test.rb`, `prompts_test.rb` |
| the process | `okf mcp` spawned for real, WEBrick on a real socket | `cli_plugin_test.rb`, `http_test.rb`, `http_modern_test.rb`, `http_listen_test.rb` |
| the argv shell | flags and exit codes, in-process, spawning nothing | `cli_test.rb` |
| units | the pieces with contracts of their own | `test/unit/` |

The three tool directories mirror the kernel's own — the three ways a bundle is
named: by directory, through the registry, and several at once.

# One claim, one place

A claim about **argv** is proven once, cheaply, in `cli_test.rb`, which drives
the shell in-process and deliberately spawns nothing. A claim about **the
process** is proven once, in the spawning files. The split is deliberate: every
spawn is seconds, and a suite that spawns for argv claims spends minutes
proving something a method call already settled.

The three HTTP files share one harness, `test/integration/http_harness.rb`, so
they cannot drift in how they compose the bridge — the same reason
[`App`](../structure/doors.md) is a single construction site in `lib/`.

# Reading the wire, which is where SSE tests go wrong

Two rules, both learned the hard way, and neither optional:

**Use a raw `TCPSocket`, not `Net::HTTP`.** Net::HTTP holds a chunked body
until EOF, so a stream that stays open — which is the whole point of
`subscriptions/listen` — reads as a hang rather than as a passing test.

**Thread `read_until`'s returned buffer back in.** One `readpartial` can carry
the next frame along with the awaited one, so a sequential read that starts
from an empty buffer drops a frame and then blocks waiting for it.

# The bundle is pinned too

`test/unit/bundle_catalog_test.rb` checks this bundle against the tree: every
`.rb` under `lib/` named by exactly one concept in
[`structure/`](../structure/), every path a concept names still present, and
the [tool catalog](../capabilities/tools.md) agreeing with the tools
`server.rb` defines. Structural documentation is code-derived, so it is pinned
like code rather than trusted like prose.
