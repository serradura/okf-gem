# AGENTS.md

Maintainer guide for okf-mcp — `okf-mcp` on RubyGems. A Model Context Protocol
server over [Open Knowledge Format](https://github.com/serradura/okf-gem)
bundles: any MCP-capable agent host can discover, orient in, search, and read
them, over stdio or Streamable HTTP. This file documents how to change the
code without breaking its contracts.

This gem is a sibling in the okf-gem monorepo, one directory per gem beside the
baseline `okf/` it depends on. [`../AGENTS.md`](../AGENTS.md) is the repo-level
guide and owns everything above a single gem — the layout, the PR shape, the
release-title convention, the Git attribution rule. What is here is okf-mcp's
own: its floor, its dependency limits, the server doctrine, and the transports.
Where the two overlap, the root is the general rule and this is the instance.
The doctrine in full — why each tool exists, the bounded-output rules, the
posture — lives in
[`../.okf/capabilities/mcp-server.md`](../.okf/capabilities/mcp-server.md);
this file is the working summary, that concept is the argument.

## Map

```
lib/okf/mcp.rb     the light entry: registry seam + backends, and the lazy
                   `OKF::MCP.app` — nothing protocol-shaped loads here
lib/okf/mcp/
  registry.rb      the served set: argv refs (dirs and @slugs) or the kernel
                   registry — resolved once at boot, the tools' allowlist
  filters.rb       the `dir` vocabulary in one place (it lived in two, and the
                   two copies disagreed about the root)
  backend.rb       engine detection: memory, or okf-sqlite3 when installed
  memory_backend.rb  the always-present folder cache: residency, fingerprints
  server.rb        the MCP::Server definition — fourteen tools, two prompts —
                   plus the per-request wrap (fingerprint memo, residency prune)
  output_schemas.rb  one declared result shape per tool, looked up by name so
                   an omission is deliberate (read_concept: markdown, no shape)
  resources.rb     bundles + concepts as resources; owns URI parsing, because
                   OKF ids carry slashes and the SDK's template matcher stops
                   at `[^/]+`
  prompts/         the consuming pair, shipped in-gem and read at get-time
  app.rb           the Rack seam: transport construction, in exactly one place
  http.rb          the WEBrick bridge: buffered responses, the streamed
                   `subscriptions/listen` adapter, and the teardown order
  cli.rb           the argv shell: `okf mcp`, `--http`, exit codes
lib/okf/plugin.rb  registers `okf mcp` with the kernel's command registry —
                   the gem's only entry point: there is no exe/
```

`require "okf/mcp"` loads the registry seam and the backends only. The MCP SDK,
WEBrick and the argv shell load on demand — from `okf/mcp/server`,
`okf/mcp/http`, `okf/mcp/cli`, or the lazy `OKF::MCP.app` —
and `test/unit/loading_test.rb` pins it in a clean subprocess: a bare require
defines neither `::MCP` nor `::WEBrick`.

## Hard constraints

1. **Ruby >= 2.7** — the `mcp` SDK's floor, inherited, not okf's 2.4 (a
   sibling's floor is its own; the root's 2.4 API list does not bind here, but
   nothing past 2.7 may appear, in `lib/` or `test/`).
2. **Runtime dependencies are exactly `mcp` and `okf`**, and both floors are
   guarded by `test/unit/gemspec_test.rb` under one rule: **the floor tracks
   what the suite proves.** The okf floor may lead the kernel checkout but
   never lag it; the mcp pin is pessimistic (`~>`) and fails the suite the day
   the lockfile resolves past it. rack and webrick arrive via okf — never name
   them in the gemspec.
3. **No executable.** `okf mcp` through the kernel's plugin seam is the one
   door, and the dispatcher adds nothing but argv and the streams. A second
   binary was deliberately removed before the first release; adding one back
   needs an argument stronger than symmetry.
4. **Every tool is a read-only lens.** `readOnlyHint` on all fourteen, a
   `title` on all fourteen (`define_tool` requires both — a capabilities test
   pins them on the wire), `additionalProperties: false` on every input
   schema, and an output schema looked up by name. Domain failures become tool
   errors carrying the kernel's own sentences — never a bare `-32603`. Both
   channels always: the JSON text an older client reads and the same object as
   `structuredContent`.
5. **Bounded outputs, honest errors.** Every list answer carries `total`, and
   `total` means one thing on every tool: how many rows the request matched,
   before any `limit` cut them. No silent truncation, ever. Adding a tool is a
   design decision, not a convenience — tool-list weight is a real cost on
   hosts, and `dirs` + `index` + `search` already compose to most retrieval.
6. **Kernel-first.** Logic a tool needs lands in the kernel and is read from
   there (`Bundle#tag_groups`, `Bundle#stats`, the cutoff grammar) — this
   shell restates nothing it can call, so the CLI and MCP answers cannot
   drift apart.

## Transports

Stdio is the default; `--http` is the WEBrick bridge in stateless JSON mode;
`OKF::MCP.app` hands the same definition and transport to any Rack 3 server a
config.ru names (the reader's server is the reader's dependency — the
no-rackup position holds).

The bridge's one subtlety is `subscriptions/listen`: the SDK answers it with a
Rack streaming body whose callable *returns immediately*, while WEBrick ends a
proc-body response when the proc returns — so the handler thread parks in the
`Stream` adapter until the SDK ends the stream. Three consequences are
load-bearing, and `test/integration/http_listen_test.rb` pins each: teardown
closes the transport **before** WEBrick (`HTTP.stop` — WEBrick's shutdown
joins its connection threads and hangs on any open stream); the signal trap
hands teardown to a thread (a mutex in trap context is `ThreadError` on 2.7);
and listens are capped at 32 on this bridge only — each holds a WEBrick
thread and connection token, which is not true under a Rack server, where the
SDK's default stands. A dead peer is noticed by `EPIPE` raising out of a
keepalive write: that propagation is the SDK's cleanup signal, so the adapter
must never swallow it.

## Testing

Integration-first, the root's rule applied to this gem's surfaces: the tool
files drive real JSON-RPC frames through `handle_json`; `cli_test.rb` and
`http_test.rb` prove the two transports end-to-end (a spawned exe, a real
socket). The HTTP files share one harness (`test/integration/http_harness.rb`)
so the three cannot drift in how they compose the bridge. SSE tests read the
wire with a raw `TCPSocket` — Net::HTTP holds a chunked body until EOF, so a
stream that stays open would read as a hang — and sequential reads must thread
`read_until`'s returned buffer back in: one `readpartial` can carry the next
frame along with the awaited one.

A change starts with a failing test here, same as the root: red for the
predicted reason, then the code, then the same test green, unedited.

From `okf-mcp/`:

```bash
bin/setup                   # install dependencies
bundle exec rake            # test + rubocop — the default task, what CI runs
bundle exec rake test       # just the suite
```
