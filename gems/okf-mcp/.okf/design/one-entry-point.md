---
type: Constraint
title: One entry point, and no executable
description: "`okf mcp` through the kernel's plugin seam is the only door; the `exe/` that only aliased it was removed before the first release, and adding one back needs an argument stronger than symmetry."
tags: [cli, plugin, packaging, constraint]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/plugin.rb
---

# No `exe/`

`lib/okf/plugin.rb` registers `okf mcp` with the kernel's command registry, and
that is the gem's entire entry surface. `spec.executables` is empty by
omission, and `test/unit/packaging_test.rb` and `test/integration/cli_plugin_test.rb`
hold the line from opposite ends — one that nothing ships, one that the verb
works when spawned as a real process.

The removed executable did nothing but call the same `CLI.run`. It went before
the first release, while dropping a name still cost nobody anything. What it
would have cost forever: a second name to install, document, keep working and
keep in step with the verb's argument grammar.

`okf-tui` made the same call for the same reason, and `okf-pro` made it for a
sharper one — its hook wrapper has to recognise exactly one `okf` binary.

# The dispatcher adds nothing

Between `okf mcp` and `OKF::MCP::CLI.run` there is argv and the streams, and
nothing else. That is what makes the plugin seam honest: a verb behaves like a
built-in because it *is* dispatched like one, and nothing about being an addon
shows up in how it is invoked or how it exits.

Adding a binary back needs an argument stronger than symmetry with gems that
have one.
