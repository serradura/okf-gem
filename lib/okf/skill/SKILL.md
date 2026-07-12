---
name: okf
description: >-
  Be the expert on Open Knowledge Format (OKF) — portable knowledge as a directory
  of markdown files with YAML frontmatter that both humans and agents read. The
  skill carries the judgment — modelling concepts, curating bundles, interpreting
  what the tools report — and routes every mechanical question (validation,
  linting, views, the graph server) to the installed `okf` CLI. Use whenever
  capturing project knowledge (services, APIs, schemas, metrics, runbooks,
  decisions) into a bundle, updating one after code or docs change, checking a
  bundle's conformance or curation quality, rendering it as a graph, or working in
  a repo that contains an OKF bundle — a `.okf/` directory or a root `index.md`
  carrying `okf_version`. Triggers on: "document this in OKF", "update the
  knowledge bundle", "capture this as a concept", "validate/lint/serve the
  bundle", or a task needing knowledge from an OKF bundle already in the repo.
user-invocable: true
argument-hint: "[produce|maintain|consume|<okf-cli-verb>] [dir] [--flags]"
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

## The CLI is your eyes — you are the judgment

Guard once, then trust it — the `okf` executable answers every mechanical question
deterministically, and its read views show everything the browser UI does:

```bash
command -v okf >/dev/null || echo "okf CLI missing — install: gem install okf (or from a checkout: cd gem && bundle exec rake install)"
```

Don't memorize the surface — `okf --help` maps every verb, `okf <verb> --help` its
flags. The division of labour is the whole game:

- **Shell out — never eyeball —** anything a verb computes: conformance (§9), what
  exists, what links where, what's stale, the map. Every read verb takes `--json`
  and the list views filter by type/area/tag, so ask the narrow question instead of
  paging the bundle.
- **You judge — the CLI can't —** meaning: contradictions, semantic staleness
  (parses fine, no longer true), whether a loose file is terminal-by-design, whether
  a singleton tag is a deliberate marker. Tool output is evidence, never a verdict.

The one trap worth carrying in your head: **freshness is off by default** — a plain
`okf lint` never reports stale concepts; pass `--stale-after <90d|12w|ISO-date>`
when the bundle carries timestamps.

Read [cli.md](reference/cli.md) before *interpreting* a verb's output in depth:
what `validate` may and may not reject, lint's categories and check ids, the JSON
shapes, the tag-curation views, the server's trust boundary.

## Orient before you touch anything

Picking up a bundle you don't already know — to consume or maintain — run `okf
index <dir>` (the §6 map: every directory's index body, rollups, and listings) and
read `log.md` (the §7 baseline of what changed last) **before** greping or opening
leaves. It is the cheapest high-signal context, and the only reliable way to catch
enumeration drift: **grep cannot find an index entry that is missing** — you can't
search for the word that should be there but isn't. Per-verb steps are in
[authoring.md](reference/authoring.md) (no `okf` installed? read the root
`index.md` plus each area's `index.md`).

## The authoring verbs — the craft

`produce` (create or extend a bundle), `maintain` (sync it with reality),
`consume` (use it as context) carry the judgment the executable can't — this is
where the skill earns its keep. Read [authoring.md](reference/authoring.md)
before doing them, and the verbatim spec [SPEC.md](reference/SPEC.md) when you
need chapter and verse.

**No subcommand?** Infer intent: "document this / capture X" → `produce`; "the
code changed, update the docs" → `maintain`; a repo already carrying a bundle
plus a task needing its knowledge → `consume`; "check / graph / preview it" →
run the matching CLI verb and interpret the result. When genuinely ambiguous,
ask.

**Which directory?** Use the path given. Otherwise default to `.okf/` at the repo
root, but first detect whether the project already keeps its bundle elsewhere
(e.g. `docs/`) and prefer that. Commit the bundle alongside the code it describes.

## The lifecycle is a flywheel, not phases

produce seeds a bundle; consume reads it; **maintain** runs whenever reality drifts
*or* whenever consuming teaches you something durable — that write-back reflex is
what keeps a bundle alive instead of rotting into folklore. When you learn
something while consuming, switch to maintain and record it. Full playbooks and the
modelling craft (granularity, choosing `type`, tag vocabulary, topology,
`resource`, links, citations) are in [reference/authoring.md](reference/authoring.md).
