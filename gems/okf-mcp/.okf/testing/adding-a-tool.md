---
type: Playbook
title: Adding a tool, end to end
description: The walk a fifteenth tool owes — the question to answer before writing it, where the code goes, the four files that gain a test, and the three pins that will refuse it if a step is skipped.
tags: [testing, tools, playbook, contribution]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/server.rb
---

# First, the question that usually ends it

**Do the [fourteen](../capabilities/tools.md) already compose to this?**
`dirs` + `index` + `search` answer most retrieval between them, and tool-list
weight is a real cost on every host that connects. A tool that duplicates a
composition is a permanent tax for a one-time convenience.

Second question: **could the kernel answer it?** If it could, it should — see
[kernel-first](../design/kernel-first.md). A kernel method serves the CLI, the
graph server, the TUI and this shell; a tool here serves one.

If both answers are no, the walk is below.

# The walk

1. **Write the failing test first**, in the folder that matches how the bundle
   is named — `test/integration/by_dir/<tool>_test.rb` at minimum, and
   `by_registry/` and `across_bundles/` if the tool takes a bundle ref or
   several. Drive real JSON-RPC through `handle_json`. Run it: it must fail
   because the tool does not exist, not because a fixture is missing.
2. **Add the kernel call**, if the analysis is not already there. That is a
   change to `okf`, with its own test, landing first.
3. **Add the builder** — `<name>_tool(context)` in `lib/okf/mcp/server.rb`,
   beside its neighbours, and list it in `tools_for`. Use `define_tool`, which
   is what attaches `readOnlyHint`, the `title` and the output-schema lookup;
   nothing else may construct a tool.
4. **Declare the output shape** in `lib/okf/mcp/output_schemas.rb`, keyed by
   the tool's name. Omit it only for a markdown answer, and expect to defend
   the omission — `read_concept` is the only one today.
5. **Carry `total`** if the answer is a list: how many rows matched *before*
   any `limit`. No silent truncation, ever.
6. **Reuse the `dir` vocabulary** from `lib/okf/mcp/filters.rb` if the tool
   takes a `dir`, and `check_dir!` for the refusal. Do not write a third
   opinion about what the root means — that bug has already happened once.
7. **Update [the catalog](../capabilities/tools.md)** with the tool's row.
8. **Run the suite.** The same test from step 1 passes, unedited.

# The three pins that refuse a skipped step

- `test/integration/capabilities_test.rb` reads the wire and fails a tool
  missing `readOnlyHint` or `title`.
- `test/integration/output_schema_test.rb` checks each declared shape against
  the answer actually sent.
- `test/unit/bundle_catalog_test.rb` fails when the catalog and `server.rb`
  disagree about which tools exist — so step 7 is not optional, and forgetting
  it is a red suite rather than a stale document.

# Adding a file, not a tool

A new file under `lib/` needs a line in whichever
[structure](../structure/) concept owns its layer — or a concept of its own if
it is a new layer. `bundle_catalog_test.rb` fails on an unowned file, which is
the point: the Map used to live in `AGENTS.md` where nothing checked it, and it
went stale silently.
