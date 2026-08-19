---
type: Component
title: The served set, and the cache in front of it
description: Which bundles this server will answer about — resolved once at boot as the tools' allowlist — plus the folder cache, the engine detection and the one place the `dir` vocabulary lives.
tags: [mcp, registry, cache, backend, filters]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/registry.rb
---

# The files

| file | what it owns |
| ---- | ------------ |
| `lib/okf/mcp/registry.rb` | `OKF::MCP::Registry` — the served set: argv refs (dirs and `@slug`s) or the kernel registry, resolved once at boot |
| `lib/okf/mcp/filters.rb` | `OKF::MCP::Filters` — the `dir` vocabulary: folding, normalizing, containment, depth |
| `lib/okf/mcp/backend.rb` | `OKF::MCP::Backend` — engine detection: the in-memory backend, or `okf-sqlite3` when it is installed and suitable |
| `lib/okf/mcp/memory_backend.rb` | `OKF::MCP::MemoryBackend` — the always-present folder cache: residency, fingerprints, catalog rows, search pairs |

# The registry is an allowlist, not a lookup

`Registry.from_argv` and `Registry.from_kernel` resolve **once, at boot**. After
that the entry list is fixed, and `#root!` is the only way a tool turns a bundle
name into a path — it raises for anything not in the set.

That is the containment property the whole server rests on: a host cannot ask
this process to read a bundle nobody served it. `#refresh!` re-reads the same
sources; it does not widen the set.

Identity comes from the kernel's registry, never minted here when a kernel slug
exists — `resolve_arg`, `ref_entry` and `group_roots` all defer to it, so
`@handbook` means the same bundle to `okf lint` and to a host. Groups expand to
their member roots, recursively, at resolve time.

# The `dir` vocabulary lives in exactly one file

`Filters` exists because it did not. The folding, normalizing and containment
rules lived in two places and **the two copies disagreed about the root** —
one treated `""` as "everything", the other as "the root directory only". Every
tool that takes a `dir` now reads them from here.

`normalize_dir`, `within?`, `dir_depth` and `known_dir?` are the whole surface.
A new tool taking a `dir` uses them rather than writing a third opinion.

# The cache is per-root and fingerprinted

`MemoryBackend#folder` caches an `OKF::Bundle::Folder` per root;
`#fingerprint` is what decides whether a cached one is still good. `#retain`
prunes roots that are no longer served, and `#during_request` memoizes
fingerprints for the span of one request so a single frame does not stat the
same tree repeatedly.

`Backend.detect` is the seam for a faster engine: if `okf-sqlite3` is installed
and `suitable?`, it is used; otherwise the memory backend, which is always
present. Nothing above this layer knows which one answered:
[the server definition](server-definition.md) asks the backend, never the
engine.
