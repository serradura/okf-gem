---
type: Capability
title: The Library — What `require "okf"` Gives You
description: The model, the analysers and the on-disk handles, without the argv machinery; plus the writer, which is the one surface no CLI verb reaches.
tags: [library, api, loading, capabilities]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf.rb
---

# What loads, and what does not

`require "okf"` loads **the library only** — the model, the analysers, search,
and the on-disk handles. The two argv-facing shells load on demand:
`lib/okf/cli.rb` (and its `optparse`) and `lib/okf/skill.rb`. `exe/okf` requires
them, and so must any test that drives them.

An embedding application never pays for the command-line machinery, and
`test/unit/loading_test.rb` guards that in a clean subprocess. Keep it green
when you change what `require "okf"` pulls in.

# The shape of an embedding

```ruby
folder = OKF::Bundle::Folder.load("docs")

folder.validate          # => Validator::Result
folder.lint(today: Date.today)
folder.graph             # => Bundle::Graph
folder.catalog           # rows, the same ones --json prints
folder.stats
folder.skeleton          # dirs, arcs, suggested cut
folder.references
```

`Folder` is the handle to hold. Everything above it in the ecosystem — the CLI,
the server, the TUI, the MCP shell — holds one, which is what keeps four
surfaces from disagreeing about the same number.

# The one surface no verb reaches

**`Bundle::Writer` has no CLI verb.** Nothing in `okf` writes a bundle: authoring
is the skill's job and the user's. So the writer is the *library API's* to prove,
and low integration coverage there is expected rather than a hole — the reverse
is true of `cli/`, `registry.rb` and `server/`, where an uncovered line is a path
a user can reach that no user-shaped test walks.

It is worth using rather than reaching for `File.write`: it locks, writes to a
temporary tree, **validates**, and only then promotes atomically. A bundle that
would not validate is never published.

# Two extension points, one shape

`OKF::CLI.register` adds a verb; `OKF::Bundle::Search.register` adds a search
engine. Both are append-only, idempotent by id, and duck-type checked at
registration — the same shape on purpose, so that learning one teaches the
other. See [structure/the-cli](/structure/the-cli.md) and
[structure/search](/structure/search.md).
