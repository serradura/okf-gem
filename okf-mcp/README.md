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

Installing the gem is the whole installation: it registers an `okf mcp` verb
with the [`okf`](https://rubygems.org/gems/okf) CLI through the plugin seam, so
the server appears in `okf help` under *installed extensions*. There is no
second binary — this gem ships no executable of its own.

## Run

```bash
okf mcp <bundle-dir> [<bundle-dir>…]   # serve exactly these directories
okf mcp @handbook ./scratch            # registry refs and plain dirs mix
okf mcp                                # no args: serve the registered bundles (okf registry)
okf mcp --http                         # one warm HTTP process instead of stdio-per-host
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
    "okf": { "command": "okf", "args": ["mcp"] }
  }
}
```

Claude Code:

```bash
claude mcp add okf -- okf mcp
```

Both serve whatever `okf registry` lists; add directories or `@slug`s to `args`
to pin the set instead.

If the host reports that it cannot spawn `okf`, it is resolving a different
`PATH` than your shell — give it the absolute path to the binstub
(`which okf`), whose shebang pins its own Ruby and so needs neither `PATH` nor
a version manager's shim to be set up.

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

Each returns its JSON twice: as text, and as `structuredContent` against a
declared `outputSchema`, so a host consumes a result without parsing a blob and
guessing at its shape. `read_concept` is the exception — markdown has no object
shape to declare.

## Prompts

Eight prompts serve the okf skill's playbooks — `okf-menu`, `okf-search`,
`okf-produce`, `okf-migrate`, `okf-maintain`, `okf-refine`, `okf-consume`,
`okf-curate` — read from the installed kernel so they version with it, and
listed in the skill's own order so the two surfaces read alike. `okf-menu` is
the front door: it orients on the signals and recommends a move rather than
running one.

The authoring playbooks are here even though every tool is read-only, because a
prompt is instructions rather than a capability — the writing is done by your
own tools, exactly as it is when the skill is installed as a skill. The one
playbook not offered is `doctor`, which installs the CLI; if this server is
answering, it is already installed.

## Resources

Every bundle with a root `index.md` is a resource at `okf://<slug>`, and every
concept is one under the template `okf://{bundle}/{id}` — so a host can *attach*
a document to the context directly, instead of the model having to decide to
fetch it. Both are read live from disk, and `bundle` and `id` complete, so the
template is browsable rather than a shape you have to know.

Concepts are not enumerated in `resources/list`: that would mean reading every
bundle at boot, which is the eager work the residency layer exists to avoid, and
would freeze a list the fingerprint check is meant to keep honest.

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
