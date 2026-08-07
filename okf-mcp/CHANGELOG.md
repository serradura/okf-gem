# Changelog

## [Unreleased]

### Fixed

- **Containment**: in argv mode the served set is now closed. Resolving an
  `@ref` at boot no longer leaves the kernel registry reachable from a
  request, so a group slug passed to `search` can no longer return content
  from bundles the operator did not serve, and `list_bundles` no longer
  advertises groups naming them.
- An unrecognized tool argument is an actionable tool error naming the key
  (schemas are closed, and `ArgumentError` is caught) instead of a bare
  JSON-RPC `-32603`. This also stops `search` silently absorbing the singular
  `bundle:` and widening its answer to every bundle.
- `lint(group: "folder")` refuses the check and threshold options it cannot
  honour rather than ignoring them and returning the full listing as though
  they had applied.
- `--bind 0.0.0.0` is reachable: a wildcard bind allowlists this machine's own
  addresses and hostname (plus the new repeatable `--allow-host`), where it
  previously allowlisted a Host string no client sends and answered 403.
- One `dir` vocabulary across every tool: `""`, `"/"`, `"."` and `"root"` all
  name the bundle root, matching is case-insensitive everywhere, and an empty
  filter means "no filter" rather than "match nothing".
- `catalog`, `search` and `graph` surface the count of files the reader could
  not parse, so a bundle with unreadable files no longer answers as if whole.
- `search(bundles: [])` names the empty argument instead of reporting every
  bundle as missing from disk.
- The residency fingerprint carries each file's size as well as its mtime, so
  a second save inside one filesystem timestamp tick is seen, and a file that
  vanishes between the glob and the stat no longer answers the tool with an
  errno.
- The prepared-corpus cache is bounded (LRU, 4) and order-insensitive, where a
  long-lived `--http` process previously retained one full index per bundle
  subset queried.
- The WEBrick bridge enforces a 4 MiB request-body cap before allocating,
  where it previously materialized any body whole and defeated the transport's
  own limit. Chunked requests carrying no `Content-Length` are served rather
  than crashing the size check.
- `rake release` tags `okf-mcp/vX.Y.Z`. Without the prefix it cut a bare
  `v0.1.0`, which the Docker workflow's `v*` trigger matches — republishing
  the `okf` image, `:latest` included, from a release that ships something
  else.

## [0.1.0] - 2026-07-24

The read surface: an MCP server over the okf kernel, judged by the kernel's own
contracts.

### Added

- Ten read-only tools mapped straight onto the kernel's library API:
  `list_bundles`, `dirs`, `index`, `search`, `read_concept`, `catalog`, `log`,
  `validate`, `lint`, `graph`. Every list output is bounded with a visible
  `total`; annotations are honest (`readOnlyHint` on all ten); domain failures
  surface as tool errors carrying the kernel's own sentences.
- Bundle identity delegated to the kernel registry: every `bundle` argument is
  a registry slug — the identity `@slug` resolves at the CLI and `/b/<slug>/`
  mounts on the hub. Argv roots are the allowlist (refs and plain dirs mix,
  registered slugs reserved before basenames are deduped); no argv serves the
  active registry, project-local discovery and `OKF_NO_DISCOVERY` included.
  Groups fan out for `search` and are refused by every single-bundle tool;
  `"*"` tolerates a vanished directory (`skipped` named in the payload) while
  naming one demands it.
- The residency layer: one parsed bundle per root, re-read only when the
  on-disk fingerprint moves, so bodies are always live and canonical. Index
  queries hold one shared corpus per served set — federated BM25 scores are
  comparable by construction — built on first use and dropped when any member
  changes.
- The engine doctrine, the CLI's exactly: raw-text scan by default,
  `engine: "index"` opt-in for BM25+/page parity, `fuzzy` implying the index,
  `regexp` staying on the scan, incompatible pairs refused with the fix named.
- Four prompts serving the okf skill's playbooks (`okf-consume`, `okf-search`,
  `okf-maintain`, `okf-curate`), read live from the installed kernel's canonical
  skill tree.
- Two transports over one server definition: stdio (default) and `--http` —
  Streamable HTTP in stateless JSON mode on WEBrick, with non-loopback binds
  allowlisted so the SDK's DNS-rebinding protection stays on.
- The `okf-sqlite3` seam: `Backend.detect` soft-requires the engine and duck
  types it; a missing or broken build degrades to memory silently except in
  the boot line and `list_bundles.backend`.

[Unreleased]: https://github.com/serradura/okf-gem/compare/okf-mcp/v0.1.0...HEAD
[0.1.0]: https://github.com/serradura/okf-gem/releases/tag/okf-mcp%2Fv0.1.0
