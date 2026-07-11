---
name: okf
description: >-
  Be the expert on Open Knowledge Format (OKF) — portable knowledge as a directory
  of markdown files with YAML frontmatter that both humans and agents read. This
  skill carries the judgment for modelling, curating, and reasoning about OKF
  bundles, and routes mechanical work to the installed `okf` CLI. One entry point,
  subcommand-driven like the CLI: authoring verbs (produce, maintain, consume) are
  agent-driven craft; tool verbs (validate, lint, loose, catalog, files, tags, stats,
  server, graph) delegate to
  the executable. Use whenever capturing project knowledge (services, APIs, schemas,
  metrics, runbooks, decisions) into a bundle, updating one after code or docs
  change, checking a bundle's conformance or curation quality, rendering it as a
  graph, or working in a repo that contains an OKF bundle — a `.okf/` directory or
  a root `index.md` carrying `okf_version`. Triggers on: "document this in OKF",
  "update the knowledge bundle", "capture this as a concept", "validate/lint/
  serve the bundle", or a task needing knowledge from an OKF bundle already in
  the repo.
user-invocable: true
argument-hint: "[produce|maintain|consume|validate|lint|loose|catalog|files|tags|stats|server|graph] [dir] [--flags]"
allowed-tools: Read Write Edit Grep Glob Bash
---

# Open Knowledge Format (OKF)

You are the OKF expert in this repository. OKF is **knowledge as code**: a
directory of markdown files, each with YAML frontmatter, that both humans and
agents read from the same source. It is minimal on purpose — no schema registry,
no runtime, no SDK. All the power lives in *conventions* and *judgment*, not in
enforcement. This skill is where that judgment lives; the `okf` CLI handles the
mechanics.

Two ideas govern everything:

- **Dual audience.** Every file must serve a human skimming it *and* an agent
  extracting from it. That is why bodies are structural markdown and links are
  plain markdown links — both readers already understand them.
- **The graph is emergent.** Files are nodes, markdown links are edges. You never
  declare a graph; it arises from how you link concepts. Good linking *is* good
  knowledge modelling.

## The hard rules (§9 conformance)

Three conditions, all hard — `validate` fails a bundle on any of them:

1. **§9.1** every non-reserved `.md` file has a parseable YAML frontmatter block;
2. **§9.2** every such block has a **non-empty `type`**;
3. **§9.3** every reserved file present is well-formed — a nested `index.md` has
   no frontmatter, the bundle-root `index.md` carries *only* `okf_version`, and
   `log.md` date headings are ISO `YYYY-MM-DD`.

Everything *else* is soft guidance, and consumers MUST tolerate missing optional
fields, unknown types, and broken links — a bundle is never rejected over them.

## Three lenses — hold them separate

Judging a bundle means asking three different questions. Conflating them is the
most common mistake:

| Lens      | Question                          | Tool                    | Nature                    |
|-----------|-----------------------------------|-------------------------|---------------------------|
| **Legal** | Is it conformant OKF? (§9)        | `validate`              | Binary, tolerant          |
| **Good**  | Is it navigable, complete, fresh? | `lint`                  | Advisory, structural      |
| **True**  | Is it consistent and *current*?   | *you*, over `lint --json` | Semantic — needs meaning |

`validate` is *forbidden* by §9 from failing a bundle for broken links or missing
optional fields — that is `lint`'s job. And neither tool can judge contradictions
or *semantic* staleness (a concept that parses fine but no longer matches
reality); only an agent reasoning over meaning can. That last lens is where you
earn your keep as the expert, not the executable.

## Dispatch — `/okf <subcommand> [dir] [flags]`

Pick behaviour by the first argument, mirroring the CLI. The two kinds want
different things from you.

**Authoring verbs are the craft.** `produce`, `maintain`, `consume` carry the
judgment the executable can't — this is where the skill earns its keep. Read
[authoring.md](reference/authoring.md) before doing them, and the verbatim spec
[SPEC.md](reference/SPEC.md) when you need chapter and verse.

**Tool verbs just drive the executable — guard once, then run.** You don't need to
open a reference for the common case:

```bash
command -v okf >/dev/null || echo "okf CLI missing — install: gem install okf (or from a checkout: cd gem && bundle exec rake install)"
okf validate  <dir> [--json]                     # §9 conformance   (exit 1 = non-conformant)
okf graph     <dir> [--json]                     # nodes + edges
okf lint      <dir> [--json] [--stale-after 90d] # curation quality; advisory (exit 0)
okf loose     <dir> [--json]                     # files with no graph links, by folder
okf catalog   <dir> [--json]                     # concepts + metadata (type, tags, links), by area
okf files     <dir> [--json]                     # files + titles, by folder
okf tags      <dir> [--json]                     # tags + their concepts, by count
okf stats     <dir> [--json]                     # bundle rollups (concepts, types, areas, links, tags)
okf server    <dir> [-p PORT]                    # serve the interactive graph over HTTP
```

`catalog`/`files`/`tags`/`stats` are the server's browser views as text — reach for
them (with `--json` for a machine substrate) to read a bundle at a glance without a
browser: what concepts exist, how they're foldered, which tags dominate, the shape.

The one that bites: **freshness is off by default — a plain `okf lint` never
reports stale concepts. Pass `--stale-after <90d|12w|ISO-date>`** when the bundle
carries timestamps. Open [cli.md](reference/cli.md) only for the rest of the
nuance: lint's six categories vs its 16 filterable check-ids, `--fail-on` gating,
`--min-body`, and the server's trust boundary.

| Subcommand  | Kind      | Do this                                                          |
|-------------|-----------|-----------------------------------------------------------------|
| `produce`   | authoring | Create or extend a bundle from code, docs, or manual knowledge. |
| `maintain`  | authoring | Sync a bundle with reality after a change.                      |
| `consume`   | authoring | Use a bundle as context for the task at hand.                   |
| `validate`  | tool      | Check §9 conformance.                                           |
| `lint`      | tool      | Report curation-quality findings (advisory).                   |
| `loose`     | tool      | List files with no graph links (degree 0), grouped by folder.  |
| `catalog`   | tool      | List concepts with metadata (type, tags, links), grouped by area. |
| `files`     | tool      | List files with titles, grouped by folder.                     |
| `tags`      | tool      | List tags with their concepts, ordered by count.               |
| `stats`     | tool      | Bundle rollups: concepts, types, areas, cross-links, tags.     |
| `server`    | tool      | Serve an interactive graph over HTTP (Cytoscape + marked).     |
| `graph`     | tool      | Print the knowledge graph (JSON with `--json`).                |

**No subcommand?** Infer intent: "document this / capture X" → `produce`; "the code
changed, update the docs" → `maintain`; a repo already carrying a bundle plus a
task needing its knowledge → `consume`; "check / graph / preview it" → the matching
tool verb. When genuinely ambiguous, ask.

**Which directory?** Use the path given. Otherwise default to `.okf/` at the repo
root, but first detect whether the project already keeps its bundle elsewhere
(e.g. `docs/`) and prefer that. Commit the bundle alongside the code it describes.

## The lifecycle is a flywheel, not phases

produce seeds a bundle; consume reads it; **maintain** runs whenever reality drifts
*or* whenever consuming teaches you something durable — that write-back reflex is
what keeps a bundle alive instead of rotting into folklore. When you learn
something while consuming, switch to maintain and record it. Full playbooks and the
modelling craft (granularity, choosing `type`, topology, `resource`, links,
citations) are in [reference/authoring.md](reference/authoring.md).
