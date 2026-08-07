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
  `total`, and the bound is on the thing the `total` counts — `log` returns the
  newest three date-grouped entries per file and names how many each holds,
  after the pre-release eval found it answering "what changed recently" with a
  whole 119,863-byte history under a `total` that was counting *files*. Every
  annotation is honest (`readOnlyHint` on all ten, and the handshake declares
  only capabilities that answer); domain failures surface as tool errors
  carrying the kernel's own sentences.
- **Structured output**: nine of the ten declare an `outputSchema` and emit
  `structuredContent` beside the JSON text, so a host consumes a result instead
  of parsing a blob and guessing. `read_concept` returns markdown, which has no
  object shape to declare.
- **Bundle identity delegated to the kernel registry**: every `bundle` argument
  is a registry slug — the identity `@slug` resolves at the CLI and
  `/b/<slug>/` mounts on the hub. One argument name on all ten tools, including
  `search`, which is the one that accepts a *set* and briefly said so by
  spelling itself `bundles`: the eval found that the plural's only signal
  arrived after a failed call, because an unknown property is refused by the
  schema before any okf sentence can be written. The type already says it takes
  an array, and the kernel spells the identity slot the same way for every verb. Argv roots are the allowlist (refs and plain
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
  an LRU of four, and dropped when any member changes. **The identity map
  follows the same rule**: served by the registry, the set of bundles tracks
  the registry file rather than a boot snapshot, so a `set`/`rename`/`del` in
  another terminal lands on the next tool call — and the `resources/list` set
  moves with it, since a resource list derived once at boot drifts out of step
  with the served set it is supposed to describe. A file that cannot be read or
  parsed keeps the last good set and retries, so a server with a working set is
  never taken down by a file it does not own. Argv mode does not follow
  anything — it never carried the registry, so its set cannot widen.
  Two consequences the re-read carries with it, both handled once per request
  rather than in each tool: the residency is **pruned to the served set**, since
  a movable set was the only thing left bounding a cache that never evicted; and
  the fingerprint is **computed once per root per request**, because freshness is
  a question between requests and asking it three times inside one cost three
  full-tree walks under the residency lock (measured: `list_bundles`, `catalog`
  and `search` each went from two walks to one, `search` on the index engine from
  three).
- **The engine doctrine, the CLI's exactly**: raw-text scan by default,
  `engine: "index"` opt-in for BM25+/page parity, `fuzzy` implying the index,
  `regexp` staying on the scan, incompatible pairs refused with the fix named.
  The payload names the engine that **answered**, resolved rather than echoed —
  `fuzzy` switches engines without being asked, and a caller cannot infer which
  ran, so a miss under the index's tokenizer was indistinguishable from a fact
  the bundle does not carry.
- **Resources**: every bundle with a root `index.md` at `okf://<slug>`, and
  every concept under the template `okf://{bundle}/{id}` — the affordance no
  tool call has, since a host can attach a document to the context without the
  model deciding to fetch it. Read live through the same residency layer
  `read_concept` uses, and closed by the same allowlist: a URI is not a path.
  Concepts are deliberately not enumerated in `resources/list`, which would
  mean reading every bundle at boot and freezing a list the fingerprint check
  exists to keep honest. The bundle list is recomputed per `resources/list` for
  the same reason — one `stat` each, no bundle read — so *listed implies
  readable* survives the registry moving.
- **Completions** for the template's `bundle` and `id`, so it is browsable
  rather than a shape you have to know. An unserved bundle, an unknown argument
  and a missing context all complete to nothing — a completion cannot be used
  to probe what argv did not serve.
- **Two prompts, the consuming pair**: `okf-search` — retrieval as progressive
  disclosure (map, then search, then only the winning bodies, with the engine
  doctrine per query shape) — and `okf-consume` — a bundle as working context
  without reading it whole. Both are this gem's own text, written against the
  tools rather than the CLI. An earlier cut served all eight of the skill's
  playbooks verbatim from the installed kernel, on the argument that a prompt
  is instructions rather than a capability; what that argument missed is
  *whose* instructions they were. Every playbook speaks in `okf …` invocations
  and half dead-end a CLI-less host at "install the CLI first", and five teach
  authoring — a mission every tool here refuses. The consuming doctrine is
  restated in tool vocabulary and shipped in this gem, which is also the cost
  accepted: a doctrine change in the skill must be carried here by hand.
- **Two transports over one server definition**: stdio (default) and `--http` —
  Streamable HTTP in stateless JSON mode on the WEBrick the kernel already
  ships. A non-loopback bind works (a wildcard `--bind 0.0.0.0` admits this
  machine's own addresses and hostname; `--allow-host` adds a name only a proxy
  or DNS knows) **and warns at boot in plain words**: every served bundle
  becomes readable, without authentication, by anything that can reach the
  port. The Host allowlist those flags feed is a DNS-rebinding defence, not
  access control — a client that is not a browser sets `Host` to whatever it
  likes — and the docs no longer imply otherwise. The bridge caps a request
  body at 4 MiB before allocating it.
- **Every failure reads as one actionable line.** A boot that cannot bind —
  `okf mcp --http` on a port already serving, which is the likeliest mistake on
  the flag that exists so one warm process is shared — printed an eleven-frame
  backtrace and exited 1 while every other boot failure exited 2 with a sentence;
  `SystemCallError` is rescued with the rest now.
- **The `okf-sqlite3` seam**: `Backend.detect` soft-requires the engine and
  duck types it; a missing gem, an unloadable native extension and an engine
  that will not construct all degrade to memory, silently except in the boot
  line and `list_bundles.backend`.
- **The `dir` vocabulary in one place**, since two copies of a rule are two
  answers waiting to disagree: `"."` and `"/"` both name the bundle root, a
  trailing slash is ignored, matching folds case, and a blank value is "no
  filter" rather than a third spelling of the root — a client that fills every
  declared optional property with `""` is doing something routine and must not
  be read as asking for the root. Not the CLI's other spelling either: `--dir
  root` exists there because a shell needs no quoting for it, and importing that
  into a JSON argument would cost any bundle with a real `root/` directory the
  ability to name it.
- **A `dir` that names no directory is refused by every tool that takes one.**
  `dirs` and `index` have always said so; `catalog` and `search` answered
  `total: 0` and no error, which is the same empty-answer-that-reads-real this
  gem refuses everywhere else. It was worst for the spelling the CLI and the
  bundled skill both teach: an agent asked `catalog` for `root`, was told zero,
  and reported that the bundle root holds no concepts. Across bundles the
  refusal is a fact about the *searched set* — a directory one of three bundles
  has still filters and does not refuse.
- **`total` means one thing on every tool**: how many rows the request matched,
  before any `limit`. `dirs` and `index` reported the whole bundle's directory
  count so a narrowing stayed visible — defensible alone, wrong as a set, and
  against this gem's own "no silent truncation" promise it read as rows withheld
  by a tool that takes no limit at all.
- **A log with no `## ` headings is bounded instead of returned whole.** §7 fixes
  no heading level, so `###` date groups are conformant and the entry split
  cannot see them: the file came back entire under `total: 0, returned: 0` — the
  one unbounded read on this surface surviving the change that was meant to close
  it, and reporting itself as empty. It now counts as the one indivisible entry
  it is, is cut by size with `truncated: true` saying so, and `limit` scales that
  budget, which it previously could not reach at all.

[Unreleased]: https://github.com/serradura/okf-gem/commits/main/okf-mcp
