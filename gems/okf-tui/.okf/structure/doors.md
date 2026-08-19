---
type: Component
title: The Doors, and What Loads When
description: One entry point through okf's plugin seam, an argv shell that loads on demand, and a ref grammar subclassed from okf rather than rewritten.
tags: [structure, cli, plugin, loading]
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/tui.rb` | `OKF::TUI`, `OKF::TUI::Error`, and the two capability probes |
| `lib/okf/plugin.rb` | `OKF::CLI::Tui` — registers `okf tui`, the gem's only entry point |
| `lib/okf/tui/cli.rb` | `OKF::TUI::CLI` — the only layer that parses argv, prints, and exits |
| `lib/okf/tui/refs.rb` | `OKF::TUI::Refs` — argv to bundle dirs, through okf's own ref grammar |
| `lib/okf/tui/version.rb` | `OKF::TUI::VERSION` |

# One door, and what that costs the dispatcher

There is **no executable**. `okf tui` is the whole surface, and the reasoning is
[one-door-the-plugin-seam](/decisions/one-door-the-plugin-seam.md).

The consequence to hold on to: **the dispatcher must add nothing but argv and
the streams.** `plugin_test.rb` pins it by driving the same run both through
`OKF::CLI.start` and straight into `CLI.run`, comparing the exit code and the
message.

`help_rows` is a promise as much as a help line. It read `tui [DIR|@slug…]` for
a whole release while the CLI rejected every `@slug` as "not a directory", so
the test now asserts the advertised form actually resolves.

# The ref grammar is okf's

`Refs` subclasses `OKF::CLI::Command`, so `@slug`, a bare `@`, an `@group` and
the refusal of `@all` mean exactly what they mean to `okf server` — same
messages, same exit codes. It reaches a *private* helper
(`resolve_ref_expanding`), which is a deliberate trade: one copy of the grammar,
at the cost of a coupling that `refs_test.rb` pins **by name**, so okf moving it
fails loudly rather than quietly restoring "not a directory".

The same call is what opts this gem into registry discovery, since okf's
`open_registry` is `Registry.load(cwd: Dir.pwd)` — which is why the TUI resolves
the same registry every other `okf` verb run from that directory resolves. See
[which-registry](/interaction/which-registry.md).

# What loads when

`require "okf/tui"` loads the library only. `cli.rb` arrives on demand — the
plugin's `#call` requires it, and so must any test that drives it.

That is not tidiness. okf reads `plugin.rb` whenever a verb misses or `okf help`
runs, so it must stay cheap: it registers a class and nothing else, and the TTY
toolkit is required inside `#call`. A subprocess test asserts that loading the
plugin leaves `TTY::Box` undefined.

`OKF::TUI.search_capable?` and `.spec_capable?` are the other half of that
caution — they ask the installed okf what it can do rather than assuming a
version, which is [okf-capability-drift](/decisions/okf-capability-drift.md).
