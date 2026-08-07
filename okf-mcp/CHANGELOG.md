# Changelog

## [Unreleased]

The first release: an MCP server over the okf kernel, judged by the kernel's
own contracts. Nothing precedes it — a `0.1.0` section stood here for a version
that was cut in this file and never published, and its entries have folded in
rather than pretending to be changes somebody could have seen.

### Added

- **`okf mcp`** — the entry point, and the only one. The gem ships no
  executable: it registers a verb with the kernel CLI through the
  `okf/plugin.rb` seam, so installing it is the whole installation and the
  server appears in `okf help` under *installed extensions*. The MCP SDK loads
  only when the verb runs, so `okf help` never pays for it.
- **Ten read-only tools** mapped straight onto the kernel's library API:
  `list_bundles`, `dirs`, `index`, `search`, `read_concept`, `catalog`, `log`,
  `validate`, `lint`, `graph`. Every list output is bounded with a visible
  `total`; every annotation is honest (`readOnlyHint` on all ten, and the
  handshake declares only capabilities that answer); domain failures surface as
  tool errors carrying the kernel's own sentences.
- **Structured output**: nine of the ten declare an `outputSchema` and emit
  `structuredContent` beside the JSON text, so a host consumes a result instead
  of parsing a blob and guessing. `read_concept` returns markdown, which has no
  object shape to declare.
- **Bundle identity delegated to the kernel registry**: every `bundle` argument
  is a registry slug — the identity `@slug` resolves at the CLI and
  `/b/<slug>/` mounts on the hub. Argv roots are the allowlist (refs and plain
  dirs mix, registered slugs reserved before basenames are deduped); no argv
  serves the active registry, project-local discovery and `OKF_NO_DISCOVERY`
  included. The allowlist is closed at boot as a property of the object rather
  than a promise: argv mode does not retain the kernel registry, so no tool
  argument and no resource URI can widen the served set. Groups fan out for
  `search` and are refused by every single-bundle tool; `"*"` tolerates a
  vanished directory (`skipped` named in the payload) while naming one demands
  it.
- **The residency layer**: one parsed bundle per root, re-read only when the
  on-disk fingerprint (mtime *and* size) moves, so bodies are always live and
  canonical. Index queries hold one shared corpus per served set — federated
  BM25 scores are comparable by construction — built on first use, bounded by
  an LRU of four, and dropped when any member changes.
- **The engine doctrine, the CLI's exactly**: raw-text scan by default,
  `engine: "index"` opt-in for BM25+/page parity, `fuzzy` implying the index,
  `regexp` staying on the scan, incompatible pairs refused with the fix named.
- **Resources**: every bundle with a root `index.md` at `okf://<slug>`, and
  every concept under the template `okf://{bundle}/{id}` — the affordance no
  tool call has, since a host can attach a document to the context without the
  model deciding to fetch it. Read live through the same residency layer
  `read_concept` uses, and closed by the same allowlist: a URI is not a path.
  Concepts are deliberately not enumerated in `resources/list`, which would
  mean reading every bundle at boot and freezing a list the fingerprint check
  exists to keep honest.
- **Completions** for the template's `bundle` and `id`, so it is browsable
  rather than a shape you have to know. An unserved bundle, an unknown argument
  and a missing context all complete to nothing — a completion cannot be used
  to probe what argv did not serve.
- **Eight prompts** serving the okf skill's playbooks — `okf-menu`,
  `okf-search`, `okf-produce`, `okf-migrate`, `okf-maintain`, `okf-refine`,
  `okf-consume`, `okf-curate` — read live from the installed kernel's canonical
  skill tree, in `SKILL.md`'s own order. Every playbook but `doctor`, which
  installs the CLI and so has had its premise disproved by anything that can
  reach this server.
- **Two transports over one server definition**: stdio (default) and `--http` —
  Streamable HTTP in stateless JSON mode on the WEBrick the kernel already
  ships, with non-loopback binds allowlisted (a wildcard `--bind 0.0.0.0`
  admits this machine's own addresses and hostname; `--allow-host` adds a name
  only a proxy or DNS knows) so the SDK's DNS-rebinding protection stays on.
  The bridge caps a request body at 4 MiB before allocating it.
- **The `okf-sqlite3` seam**: `Backend.detect` soft-requires the engine and
  duck types it; a missing or broken build degrades to memory silently except
  in the boot line and `list_bundles.backend`.

[Unreleased]: https://github.com/serradura/okf-gem/commits/main/okf-mcp
