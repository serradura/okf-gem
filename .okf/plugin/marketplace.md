---
type: Component
title: The marketplace manifest
description: The repository doubles as its own Claude Code marketplace, which makes the manifest at the root a distribution surface rather than configuration.
resource: .claude-plugin/marketplace.json
tags: [plugin, marketplace, distribution]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
sources:
  - title: .claude-plugin/marketplace.json
    resource: https://github.com/serradura/okf/blob/main/.claude-plugin/marketplace.json
---

# What it is

`.claude-plugin/marketplace.json` at the repository root. It lets someone add
this repository as a marketplace and install
[the plugin](claude-code-plugin.md) from it, with nothing published anywhere
else.

That is the point of it being here: the repository *is* the distribution
channel, so a plugin release is a push rather than an upload.

# Why it is not inside `plugin/`

Two manifests, two jobs. `plugin/.claude-plugin/plugin.json` describes **the
plugin**; this one describes **the marketplace that offers it**. A marketplace
can list more than one plugin, so it cannot live inside any of them.

Both sit at a path a tool looks for by convention, which is the one kind of name
this repository lets stay at its root — see
[the monorepo layout](../decisions/monorepo-layout.md).
