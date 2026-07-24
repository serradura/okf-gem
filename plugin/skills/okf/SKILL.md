---
name: okf
description: >-
  Be the expert on Open Knowledge Format (OKF) — portable project knowledge as a
  directory of markdown files with YAML frontmatter that humans and agents read
  from one source. Use when capturing knowledge into a bundle (a service, schema,
  metric, decision, runbook: "document this in OKF", "capture this as a concept"),
  converting existing docs into one ("migrate/OKFy our docs into a bundle"),
  retrieving from one without reading it whole ("what do we know about X?", "where
  is X documented?", "search the bundle"), updating one after code or docs
  change ("update the knowledge bundle"), checking its conformance or curation
  quality ("validate/lint the bundle"), serving or rendering it as a graph, or
  working in a repo that already carries an OKF bundle — a `.okf/` directory or a
  root `index.md` carrying `okf_version`.
user-invocable: true
argument-hint: "[search|produce|migrate|maintain|refine|consume|curate|doctor|<okf-cli-verb>] [dir|@slug] [--flags]"
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

The `okf` executable answers every mechanical question deterministically, and its
read views show everything the browser UI does. **Don't probe for it — just run
the verb.** A proactive `command -v okf` before every task spends a whole tool
round proving what the next command reveals for free; the CLI's own failure is a
cheaper, truer signal. (The two deliberate exceptions are [menu](playbooks/menu.md)
and [doctor](playbooks/doctor.md) — both decide *whether to install*, so they check
first.) The one distinction to hold: a shell `okf: command not
found` is the *only* thing that means "install it" (→ [doctor](playbooks/doctor.md));
every line that starts `error:` is okf *answering* — a bundle or usage result to
read and act on, never a missing toolchain to send to doctor.

Don't memorize the surface — `okf --help` maps every verb, `okf <verb> --help` its
flags. The division of labour is the whole game:

- **Shell out — never eyeball —** anything a verb computes: conformance (§9), what
  exists, what links where, where a term lives, what's stale, the map. Every read
  verb takes `--json` and the list views filter by type/dir/tag, so ask the narrow
  question instead of paging the bundle.
- **Skeleton first, bodies last.** `dirs`, `search`, `graph --minimal`, and
  `--fields` projections each answer for a fraction of a dump's bytes; full
  bodies are the final step of a retrieval, never the first. <!-- rule:okf-skeleton-first -->
- **You judge — the CLI can't —** meaning: contradictions, semantic staleness
  (parses fine, no longer true), whether a loose file is terminal-by-design, whether
  a singleton tag is a deliberate marker. Tool output is evidence, never a verdict.

The one trap worth carrying in your head: **freshness is off by default** — a plain
`okf lint` never reports stale concepts; pass `--stale-after <90d|12w|ISO-date>`
when the bundle carries timestamps. <!-- check:stale -->

Read [cli.md](reference/cli.md) before *interpreting* a verb's output in depth:
what `validate` may and may not reject, lint's categories and check ids, the JSON
shapes, the tag-curation views, the server's trust boundary.

## Orient before you touch anything

Picking up a bundle you don't already know — to consume or maintain — start with
`okf dirs <dir|@slug>`: one row per *directory*, so it stays small on a bundle of
any size and it names the branches every other view narrows to. Then open the one
you want with `okf index <dir|@slug> --dir <branch>` (the §6 map: that directory's
index body, rollups, and listing), and read `log.md` (the §7 baseline of what
changed last) — all of it **before** greping or opening leaves. Reach for `index`
rather than grep for the one reason that outranks convenience: **grep cannot find
an index entry that is missing**, so enumeration drift is invisible to it — you
can't search for the word that should be there but isn't. <!-- rule:okf-orient-index -->
Per-verb steps are in the
playbooks (the Commands table below; no `okf` installed? read the root
`index.md` plus each area's `index.md`).

## The authoring verbs — the craft

`produce` (create or extend a bundle), `maintain` (sync it with reality),
`consume` (use it as context) carry the judgment the executable can't — this is
where the skill earns its keep. Each has a playbook (the Commands table below);
read the modelling craft in [authoring.md](reference/authoring.md) before
producing or maintaining, and the verbatim spec [SPEC.md](reference/SPEC.md)
when you need chapter and verse.

**No subcommand?** Infer intent: "document this / capture X" → `produce`;
"convert / migrate / OKFy these existing docs into a bundle" → `migrate`; "the
code changed, update the docs" → `maintain`; "restructure / rebalance the
bundle / is the structure right / get more out of it" → `refine`; "what do we
know about X / where is X documented" → `search`; a repo already carrying a
bundle plus a task needing its knowledge → `consume`; "check / graph / preview
it" → run the matching CLI verb and interpret the result. When genuinely
ambiguous, ask.

**Which target?** A leading `@` is a *registry ref*, not a path: `@slug` names a
bundle registered with `okf registry set`, bare `@` the default — route it
straight to `okf <verb> @slug` and skip the directory hunt (`okf search` spans
several: `@a @b`, or `@all`). A `@slug` may instead name a **group** — a saved set
of bundles (`okf registry group backend @a @b`, members nest); it resolves like
any ref for the two set-taking verbs (`okf search @backend`, `okf server
@backend`) and every single-bundle verb refuses it with exit 2, the message
saying which two take a group. A plain path is used as given. Given no target and a
cwd that carries no bundle, `okf registry list` is the next move, not a hunt
across sibling directories. Producing a *new* bundle with no path? Default to
`.okf/` at the repo root, but first detect whether the project already keeps its
bundle elsewhere (e.g. `docs/`) and prefer that; commit it alongside the code it
describes.

**Target isn't a bundle?** When a verb points at a directory that holds markdown
but no root `index.md` carrying `okf_version` — `validate` failing wholesale on
missing frontmatter — don't grind through the errors: suggest `migrate` (OKFy it
in place, bodies verbatim) and let the user pick.

## Commands

The first word of the arguments picks a row. **No arguments at all** — someone
asking "what should I do?" — is its own row: read `playbooks/menu.md`, orient on
the signals, and recommend the highest-value move without running one. When there
is wording but no matching first word, infer intent as in "No subcommand?" above.
Read the referenced playbook before executing — it *is* the procedure.

| Verb | Category | What it does | Reference |
|------|----------|--------------|-----------|
| *(none)*   | Orient | recommend the highest-value next move; never auto-run | [playbooks/menu.md](playbooks/menu.md) |
| `search`   | Use    | answer a question from the bundle: map → finder → only the winning bodies | [playbooks/search.md](playbooks/search.md) |
| `produce`  | Author | create or extend a bundle | [playbooks/produce.md](playbooks/produce.md) |
| `migrate`  | Author | convert existing docs in place: frontmatter + reserved files, bodies verbatim | [playbooks/migrate.md](playbooks/migrate.md) |
| `maintain` | Author | sync the bundle's content with reality after a change | [playbooks/maintain.md](playbooks/maintain.md) |
| `refine`   | Author | optimize the bundle's structure: evidence-driven, cohesion-first; proposes, never auto-applies | [playbooks/refine.md](playbooks/refine.md) |
| `consume`  | Use    | use the bundle as context for a task | [playbooks/consume.md](playbooks/consume.md) |
| `curate`   | Curate | structural upkeep as it stands: validate + lint + loose | [playbooks/curate.md](playbooks/curate.md) |
| `doctor`   | Setup  | install and verify the CLI, then doctor the bundle | [playbooks/doctor.md](playbooks/doctor.md) |
| `<okf-cli-verb>` | Read | validate, lint, loose, index, catalog, files, tags, types, stats, graph, server, render, registry, skill — **plus any verb an installed extension adds** (`okf help` is authoritative, this list is not) | `okf <verb> --help` + [reference/cli.md](reference/cli.md) |

Three boundaries worth keeping sharp: `curate` is structural upkeep only — when
the *content* no longer matches reality, that is `maintain`, and when the
content is right but the *shape* underserves retrieval, that is `refine` — and
`doctor` is the one playbook that does not assume the CLI is installed. In
Claude Code with the okf plugin, `/okf:gem` routes these same verbs.

## The lifecycle is a flywheel, not phases

produce seeds a bundle; consume reads it; **maintain** runs whenever reality drifts
*or* whenever consuming teaches you something durable — that write-back reflex is
what keeps a bundle alive instead of rotting into folklore. When you learn
something while consuming, switch to maintain and record it. The playbooks live
one per verb in `playbooks/` (the Commands table above); the modelling craft
(granularity, choosing `type`, tag vocabulary, topology, `resource`, links,
citations) is in [reference/authoring.md](reference/authoring.md).
