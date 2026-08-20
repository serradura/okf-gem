---
type: Component
title: The server definition
description: The MCP::Server subclass, the fourteen tool builders and the private helpers they share, one declared output shape per tool, and concepts as resources with a URI parser the SDK's matcher cannot supply.
tags: [mcp, server, tools, schemas, resources]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/server.rb
---

# The files

| file | what it owns |
| ---- | ------------ |
| `lib/okf/mcp/server.rb` | `OKF::MCP::Server` — `Server::Definition < ::MCP::Server`, `Server.build`, the fourteen `*_tool` builders, the two prompts, and the shared private helpers |
| `lib/okf/mcp/output_schemas.rb` | `OKF::MCP::OutputSchemas` — one declared result shape per tool, looked up by name |
| `lib/okf/mcp/resources.rb` | `OKF::MCP::Resources` — bundles and concepts as MCP resources, and the URI grammar |

# server.rb is one file on purpose, in three bands

At ~1,300 lines it is the largest file in the gem, and splitting it has been
considered and declined: the fourteen builders are near-identical in shape, and
what makes them safe is that they sit next to each other where a divergence is
visible. Read it as three bands.

**`Server.build` and `Definition`.** `build` assembles the definition from a
registry and an engine. `Definition` subclasses the SDK's server and adds the
per-request wrap: `#in_request` memoizes fingerprints and `#retain_served`
prunes cache residency, so a frame's repeated reads cost one stat. `#handle`
and `#handle_json` are what the tests drive — real JSON-RPC frames, no
transport involved.

**The fourteen builders**, one per tool: `tags_tool`, `types_tool`,
`stats_tool`, `list_bundles_tool`, `dirs_tool`, `index_tool`, `search_tool`,
`read_concept_tool`, `catalog_tool`, `log_tool`, `validate_tool`, `lint_tool`,
`graph_tool`, `references_tool`. Each is a `define_tool` call and a body that
calls the kernel. The [tool catalog](../capabilities/tools.md) is the reader's
map of them.

**The shared helpers**, which are where the contracts actually live:
`define_tool` (the one place `readOnlyHint`, `title` and the output-schema
lookup are attached — which is why a tool cannot forget them), `respond_json`
and `respond_error`, the projection and validation helpers (`check_fields`,
`check_projection`, `check_asked`, `project_rows`), the bounded-log arithmetic
(`bounded_log`, `sized_log`), and `check_dir!`, which is the refusal every
`dir`-taking tool shares.

# One declared shape per tool, looked up by name

`OutputSchemas[name]` is a lookup, not a registry a tool writes into. An
omission is therefore deliberate and visible: `read_concept` has no shape,
because it answers markdown rather than a structured row, and that is the only
one. `test/integration/output_schema_test.rb` walks the wire and checks the
declared shape against the answer actually sent.

# Resources own the URI grammar because the SDK cannot

`Resources.parse` exists for one reason worth knowing before touching it: **OKF
concept ids carry slashes** (`capabilities/graph-server.md`), and the SDK's
resource-template matcher stops at `[^/]+`. So a templated match would truncate
every nested id. This file parses the URI itself.

`list`, `templates`, `read` and `complete` are the surface; `concept_ids` and
`prefixed` back the completion. `test/integration/resources_test.rb` and
`completions_test.rb` drive them.

# The prompts are read at get-time

`Server::PROMPTS` names two markdown files shipped in `lib/okf/mcp/prompts/`,
and `Server.prompt_text` reads one when a host asks for it. Booting never pays
for prompt bodies, and editing a prompt does not need a code change.
