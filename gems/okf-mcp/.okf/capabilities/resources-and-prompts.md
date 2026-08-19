---
type: Capability
title: Resources, completions and prompts
description: What the protocol offers that a tool call does not — bundles and concepts as addressable resources, argument completion, and the two prompts shipped in-gem and read at get-time.
tags: [mcp, resources, prompts, completion]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/resources.rb
---

# Resources: addressable, not just callable

A tool is something a host *invokes*; a resource is something it can *attach*.
Both bundles and concepts are exposed as resources, so a host can put a concept
into a conversation without spending a tool call on it.

`Resources.list` enumerates served bundles, `templates` declares the concept
template, and `read` resolves one URI. The URI grammar is parsed by hand rather
than templated — see
[the server definition](../structure/server-definition.md) for why the SDK's
matcher cannot do it.

`Resources.complete` backs argument completion, which is what makes a concept
id typeable in a host that offers completion at all. `concept_ids` and
`prefixed` are its two halves.

# Prompts: the consuming pair

Two, shipped as markdown in `lib/okf/mcp/prompts/` and named by
`Server::PROMPTS`:

| prompt | for |
| ------ | --- |
| `search` | answering a question from a bundle, token-lean: the map, then the finder, then only the winning bodies |
| `consume` | using a bundle as context for a task |

They are read at get-time by `Server.prompt_text`, so booting never pays for
their bodies and editing one is not a code change. They are written in **tool
vocabulary** — they name the tools above, not CLI verbs — because the host
reading them has no shell.

`test/integration/prompts_test.rb` walks both, and
`test/integration/resources_test.rb` and `completions_test.rb` cover the
resource surface.
