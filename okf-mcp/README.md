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

Installing the gem is the whole installation: the
[`okf`](https://rubygems.org/gems/okf) kernel arrives as a dependency, and the
gem registers an `okf mcp` verb with its CLI through the plugin seam, so
the server appears in `okf help` under *installed extensions*. There is no
second binary — this gem ships no executable of its own.

## Run

```bash
okf mcp <bundle-dir> [<bundle-dir>…]   # serve exactly these directories
okf mcp @handbook ./scratch            # registry refs and plain dirs mix
okf mcp                                # no args: serve the registered bundles (okf registry set <dir> adds one)
okf mcp --http                         # one warm HTTP process instead of stdio-per-host
```

Stdio is the default — each host spawns its own process, zero config. `--http`
(`--bind`, default 127.0.0.1; `--port`, default 9134) serves Streamable HTTP in
stateless JSON mode for every agent at once. The boot line goes to stderr and
names the backend, the served bundles, and the registry file the slugs came
from.

`--bind` beyond loopback works — a wildcard `0.0.0.0` admits this machine's own
addresses and hostname, and `--allow-host HOST` (repeatable) adds a name only a
proxy or DNS knows — and it publishes your bundles. **There is no
authentication.** Anything that can reach the port can read every served
bundle, so the boot line says so.

The Host allowlist those flags feed is a defence against **DNS rebinding**: a
browser walked into this port by a page you never meant to give it to. It is
not access control, and it cannot be — a client that is not a browser sets
`Host` to whatever it likes. Treat a non-loopback bind the way you would treat
serving your notes directory over HTTP, because that is what it is.

Whatever argv names is the whole served set. A registry ref is resolved once, at
boot; no tool argument can widen the set afterwards, so a group slug reaches
bundles only when the registry itself is what is being served.

With no arguments the registry *is* what is served, so it is followed rather
than snapshotted: `okf registry set`, `rename` or `del` in another terminal
shows up on the next tool call, without a restart. The file is re-read only
when its fingerprint moves, so the cost is a `stat`. Bundle contents are never
snapshotted either — bodies are read live, and a bundle is re-parsed whenever
one of its files changes.

## Host configuration

**Run `which okf` and paste the absolute path.** A desktop app is launched by
the window manager, not by your shell, so it never runs the rc file that puts
a version manager's Ruby on `PATH` — and if your Ruby came from mise, rbenv,
asdf or chruby, a bare `"okf"` is unresolvable there. The binstub's shebang
pins its own Ruby, so the absolute path needs nothing else set up.

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "okf": { "command": "/absolute/path/from/which/okf", "args": ["mcp"] }
  }
}
```

Claude Code inherits your shell, so the bare name is fine there:

```bash
claude mcp add okf -- okf mcp
```

Both serve whatever `okf registry` lists; add directories or `@slug`s to `args`
to pin the set instead.

## Tools

Ten read-only tools. Every list answer is bounded and names the full count it
was cut from — the rows the request matched, before any `limit`:

| Tool | What it answers |
|---|---|
| `list_bundles` | what exists: slug, title, root, concept count, type/tag rollups, the default, the groups, the backend |
| `dirs` | the shape — one row per directory with direct and subtree counts; **the first move** |
| `index` | the index map: authored index bodies, rollups, listings, one directory at a time (depth 1 by default) |
| `search` | pointed questions: ANDed terms, scored rows carrying the fields they matched, across several bundles at once |
| `read_concept` | one concept's file, verbatim and live from disk; ids are exact |
| `catalog` | per-concept metadata with link degrees; filters, paging, field projection |
| `log` | every `log.md`, root first, live — the newest 3 dated entries per file, each answer held to a byte budget `limit` scales; a cut says `truncated` |
| `validate` | the spec §9 conformance verdict |
| `lint` | the curation-quality report; `group: "folder"` lists the unlinked files by folder |
| `graph` | the knowledge graph in three bounded views: minimal, hubs, traffic — never with bodies |

Each returns its JSON twice: as text, and as `structuredContent` against a
declared `outputSchema`, so a host consumes a result without parsing a blob and
guessing at its shape. `read_concept` is the exception — markdown has no object
shape to declare.

## Prompts

Two prompts, the consuming pair: `okf-search` — retrieval as progressive
disclosure (map, then search, then only the winning bodies), with the engine
doctrine per query shape — and `okf-consume` — using a bundle as working
context without reading it whole. Both are this gem's own text, written
against the tools above rather than the CLI, so they work on a host with no
shell and no filesystem.

The okf skill's playbooks are deliberately not served. They speak in `okf …`
invocations, and the authoring ones — produce, migrate, maintain, refine,
curate — carry a mission every tool here refuses: this server makes a client
an expert *consumer* of bundles. Authoring stays with the skill
(`okf skill <dest>`), installed where a filesystem and the CLI actually are.

## Resources

Every bundle with a root `index.md` is a resource at `okf://<slug>`, and every
concept is one under the template `okf://{bundle}/{id}` — so a host can *attach*
a document to the context directly, instead of the model having to decide to
fetch it. Both are read live from disk, and `bundle` and `id` complete, so the
template is browsable rather than a shape you have to know.

Concepts are not enumerated in `resources/list`: that would mean reading every
bundle at boot — exactly the eager work this server avoids, since bundles are
parsed on first use and re-read only when their files change — and it would
freeze a list that live reading is meant to keep honest.

## Engines

Search matches raw text by default — exact, no tokenizer, milliseconds over an
already-parsed bundle. `engine: "index"` opts into BM25+ ranking on a held corpus,
the same engine and version the `okf server` page runs, so the two rank
identically. `fuzzy` implies the index and its tokenizer; `regexp` stays on the
raw-text scan; incompatible pairs are refused with the fix named.

Every result names the engine that **answered** it, because `fuzzy` picks one
without being asked and no score tells you which ran. It matters when something
is missing: under the index's tokenizer a shattered identifier and an absent
fact look identical, so knowing you were on the index is what turns "not here"
back into "try the scan". The doctrine runs the other way too — the scan is
exact, so a typo or a stemmed form misses on it, and that miss is what
`engine: "index"` and `fuzzy` are for.

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
