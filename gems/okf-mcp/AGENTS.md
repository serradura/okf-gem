# AGENTS.md

Maintainer guide for okf-mcp — `okf-mcp` on RubyGems. A Model Context Protocol
server over [Open Knowledge Format](https://github.com/serradura/okf-gem)
bundles: any MCP-capable agent host can discover, orient in, search, and read
them, over stdio or Streamable HTTP.

This gem is a sibling in the okf-gem monorepo, one directory per gem under
`gems/`, beside the baseline `gems/okf/` it depends on.
[`../../AGENTS.md`](../../AGENTS.md) is the repo-level guide and owns everything
above a single gem — the layout, the PR shape, the release-title convention, the
Git attribution rule. Where the two overlap, the root is the general rule and
this is the instance.

## Read the bundle first

**`.okf/` is this gem's structural documentation, and this file no longer
restates it.** What the code is, where each responsibility lives, what each tool
answers, why the floor is 2.7, and how to add a tool or a test all live there —
once, in the concept that owns them:

| you want | read |
| --- | --- |
| the shape of the whole thing | [`.okf/overview.md`](.okf/overview.md) |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, and it names every file |
| whether a capability already exists | [`.okf/capabilities/tools.md`](.okf/capabilities/tools.md) — the fourteen tools, before you write a fifteenth |
| why a rule is a rule | [`.okf/design/`](.okf/design/) |
| how to test a change | [`.okf/testing/`](.okf/testing/) — the layers, and the walk a new tool owes |

`okf server .okf` from this directory reads it as a graph; `okf search @okf-mcp
<term>` searches it from anywhere in the checkout.

The **doctrine** — why the tool set is what it is, the bounded-output argument,
the posture — is [`.okf/design/the-tool-set.md`](.okf/design/the-tool-set.md).
It used to live in the repository bundle, one directory up; it moved here with
the rest of this gem's knowledge, because the ecosystem's map explains no gem.

The split used to run the other way: this file carried a hand-written Map of
`lib/**` and nothing checked it. `test/unit/bundle_catalog_test.rb` now fails
when a file under `lib/` is named by no concept, when a concept names a file
that is gone, or when the tool catalog and `server.rb` disagree — so the
structural layer is pinned where it lives, rather than trusted where nobody
looks.

## The contract

Six rules. Each one's argument is in [`.okf/design/`](.okf/design/); what
follows is the short form a reviewer checks against.

1. **Ruby >= 2.7**, the `mcp` SDK's floor — inherited, not okf's 2.4. A
   sibling's floor is its own: the root's 2.4 API list does not bind here, and
   nothing past 2.7 may appear, in `lib/` or `test/`.
2. **Runtime dependencies are exactly `mcp` and `okf`.** rack and webrick
   arrive via okf — never name them in the gemspec. Both floors track what the
   suite proves: `test/unit/gemspec_test.rb`.
3. **No executable.** `okf mcp` through the kernel's plugin seam is the one
   door. Adding a binary back needs an argument stronger than symmetry.
4. **Every tool is a read-only lens.** `readOnlyHint` and a `title` on all
   fourteen, `additionalProperties: false` on every input schema, an output
   schema looked up by name. Domain failures become tool errors carrying the
   kernel's own sentences — never a bare `-32603` — and both channels always.
5. **Bounded outputs, honest errors.** Every list answer carries `total`, and
   `total` means how many rows the request matched before any `limit` cut them.
   No silent truncation, ever.
6. **Kernel-first.** Logic a tool needs lands in the kernel and is read from
   there, so the CLI and MCP answers cannot drift apart.

A change starts with a failing test, red for the reason you predicted, then the
code, then the same test green and unedited — the root's rule, unchanged.

## Commands

From `gems/okf-mcp/`:

```bash
bin/setup                   # install dependencies
bundle exec rake            # test + rubocop — the default task, what CI runs
bundle exec rake test       # just the suite
```

And from the repository root, for the bundle itself:

```bash
rake okf                    # validate + lint every registered bundle, this one included
```

## Its own bundle

`.okf/` ships inside the gem — the reject list does not name it, deliberately —
so an installed okf-mcp carries a real bundle, its own, for a host to read
through the very tools it serves. `test/unit/packaging_test.rb` pins that it
ships; `rake okf` at the repo root keeps it validated and lint-clean.

Maintain it in the same commit as the code it documents. A new file under
`lib/` without a line in the concept that owns its layer is a red suite, not a
stale document.
