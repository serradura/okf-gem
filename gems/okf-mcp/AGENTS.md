# AGENTS.md

okf-mcp — a Model Context Protocol server over OKF bundles: any MCP-capable
agent host can discover, orient in, search and read them, over stdio or
Streamable HTTP. A sibling in the okf-gem monorepo, beside the baseline
`gems/okf/` it depends on.

**This file is context, routing and reference.** [`../../AGENTS.md`](../../AGENTS.md)
binds every change in the repo; what is below is okf-mcp's own, and every
argument for it is in `.okf/` rather than here.

## Where to read

| you want | read |
| --- | --- |
| the shape of the whole thing | [`.okf/overview.md`](.okf/overview.md) |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, naming every file |
| whether a tool already answers this | [`.okf/capabilities/tools.md`](.okf/capabilities/tools.md) — the fourteen, before you write a fifteenth |
| why the tool set is what it is | [`.okf/design/the-tool-set.md`](.okf/design/the-tool-set.md) — the doctrine and the bounded-output argument |
| why a rule is a rule | [`.okf/design/`](.okf/design/) |
| how to add a tool or a test | [`.okf/testing/`](.okf/testing/) |

`okf server .okf` reads it as a graph; `okf search @okf-mcp <term>` from anywhere
in the checkout.

## The contract

Six rules. Each line is the whole of what you must hold; the link is why.

1. **Ruby >= 2.7**, the `mcp` SDK's floor — inherited, not okf's 2.4. okf's API
   list does not bind here, and nothing past 2.7 may appear, in `lib/` or
   `test/` — [`.okf/design/ruby-floor.md`](.okf/design/ruby-floor.md).
2. **Runtime dependencies are exactly `mcp` and `okf`.** rack and webrick arrive
   via okf — never name them in the gemspec. `test/unit/gemspec_test.rb` tracks
   both — [`.okf/design/runtime-dependencies.md`](.okf/design/runtime-dependencies.md).
3. **No executable.** `okf mcp` through the kernel's plugin seam is the one door
   — [`.okf/design/one-entry-point.md`](.okf/design/one-entry-point.md).
4. **Every tool is a read-only lens.** `readOnlyHint` and a `title` on all
   fourteen, `additionalProperties: false` on every input schema, an output
   schema looked up by name. Domain failures become tool errors carrying the
   kernel's own sentences — never a bare `-32603` — and both channels always.
5. **Bounded outputs, honest errors.** Every list answer carries `total`, meaning
   how many rows the request matched *before* any `limit` cut them. No silent
   truncation, ever.
6. **Kernel-first.** Logic a tool needs lands in the kernel and is read from
   there, so the CLI and MCP answers cannot drift apart —
   [`.okf/design/kernel-first.md`](.okf/design/kernel-first.md).

## Commands

```bash
bin/setup                   # install dependencies
bundle exec rake            # test + rubocop — the default task, what CI runs
bundle exec rake test       # just the suite
```

The 2.7 floor, from the repo root because the Gemfile resolves okf from `../okf`:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.7 bash -c \
  "cp -a /src /build && cd /build/gems/okf-mcp && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

## Its own bundle

`.okf/` ships inside the gem — the reject list does not name it, deliberately —
so an installed okf-mcp carries a real bundle, its own, for a host to read
through the very tools it serves. `test/unit/packaging_test.rb` pins that it
ships; `rake okf` at the repo root keeps it clean.

Maintain it in the same commit as the code. A file under `lib/` with no concept
naming it is a red suite, and so is a tool `server.rb` defines with no row in the
catalog.
