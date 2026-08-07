# okf-mcp

A [Model Context Protocol](https://modelcontextprotocol.io) server for
[OKF](https://okfgem.com) bundles: any MCP-capable agent host — Claude Desktop,
Claude Code, anything speaking the protocol — can discover, orient in, search,
and read the Open Knowledge Format bundles on a machine.

It is a thin shell over the [`okf`](https://rubygems.org/gems/okf) kernel, the
fourth surface beside its CLI, HTTP server and Ruby library: every tool maps
onto the kernel's library API, bundles are named by the same registry slugs
`@slug` resolves at the CLI, and nothing is reimplemented here.

## Install

```bash
gem install okf-mcp
```

Ruby >= 2.7 — the official `mcp` gem's own floor, inherited rather than chosen.

## Run

```bash
okf-mcp <bundle-dir> [<bundle-dir>…]   # serve exactly these directories
okf-mcp @handbook ./scratch            # registry refs and plain dirs mix
okf-mcp                                # no args: serve the registered bundles (okf registry)
okf-mcp --http                         # one warm HTTP process instead of stdio-per-host
```

Stdio is the default — each host spawns its own process, zero config. `--http`
(`--bind`, default 127.0.0.1; `--port`, default 9134) serves Streamable HTTP in
stateless JSON mode for every agent at once. The boot line goes to stderr and
names the backend, the served bundles, and the registry file the slugs came
from.

Binding beyond loopback keeps the SDK's DNS-rebinding protection on: a wildcard
`--bind 0.0.0.0` admits this machine's own addresses and hostname, and
`--allow-host HOST` (repeatable) adds a name only a proxy or DNS knows.

Whatever argv names is the whole served set. A registry ref is resolved once, at
boot; no tool argument can widen the set afterwards, so a group slug reaches
bundles only when the registry itself is what is being served.

## Host configuration

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "okf": { "command": "okf-mcp", "args": [] }
  }
}
```

Claude Code:

```bash
claude mcp add okf -- okf-mcp
```

Both serve whatever `okf registry` lists; put directories in `args` to pin the
set instead.

## Tools

Ten read-only tools, every list output bounded with a visible `total`:

| Tool | What it answers |
|---|---|
| `list_bundles` | what exists: slug, title, root, concept count, type/tag rollups, the default, the groups, the backend |
| `dirs` | the shape — one row per directory with direct and subtree counts; **the first move** |
| `index` | the index map: authored index bodies, rollups, listings, one directory at a time (depth 1 by default) |
| `search` | pointed questions: ANDed terms, scored rows carrying the fields they matched, across bundles through one shared index |
| `read_concept` | one concept's file, verbatim and live from disk; ids are exact |
| `catalog` | per-concept metadata with link degrees; filters, paging, field projection |
| `log` | every `log.md`, root first, live |
| `validate` | the spec §9 conformance verdict |
| `lint` | the curation-quality report; `group: "folder"` lists the unlinked files by folder |
| `graph` | the knowledge graph in three bounded views: minimal, hubs, traffic — never with bodies |

Four prompts — `okf-consume`, `okf-search`, `okf-maintain`, `okf-curate` —
serve the okf skill's playbooks, read from the installed kernel so they version
with it.

## Engines

Search matches raw text by default — exact, no tokenizer, milliseconds over a
resident bundle. `engine: "index"` opts into BM25+ ranking on a held corpus,
the same engine and version the `okf server` page runs, so the two rank
identically. `fuzzy` implies the index and its tokenizer; `regexp` stays on the
raw-text scan; incompatible pairs are refused with the fix named.

## Beside a browser

The MCP surface is for agents; humans get the same bundles as an interactive
graph:

```bash
okf server          # the registered bundles, one hub, http://127.0.0.1:8808
```

Run it beside the MCP config and both read the same live files.

## Development

```bash
bin/setup                          # install dependencies
bundle exec rake                   # tests + RuboCop — what CI runs
bundle exec rake test:integration  # the critical layer alone + coverage/integration/
```

## License

Apache-2.0, see [LICENSE.txt](LICENSE.txt).
