# OKF tool verbs — the `okf` CLI

`validate`, `lint`, `loose`, `search`, `index`, `catalog`, `files`, `tags`, `types`,
`stats`, `server`, `render`, and `graph` are **not** eyeball passes and are not
reimplemented in this skill. They run the deterministic `okf` executable shipped by
the companion gem — the single source of truth for OKF mechanics. Your job is to
invoke it correctly and interpret the result, not to reason out conformance by hand.
## Which file answers what

This file is the **index and the shared contract**: what every verb has in
common — refs, exit codes, `--json`, the filters — lives here, and each verb's
own semantics, traps, and JSON shape live in one file below. Read this one, then
the single row the question calls for, and stop; a leaf names its prerequisite
when it has one.

| File | Verbs | What it answers |
|------|-------|-----------------|
| [cli/checks.md](cli/checks.md) | `validate` `lint` `loose` `references` | what makes a bundle non-conformant, every lint check and the severity it is pinned at, the two clocks that share the `stale_after` spelling, why loose ≠ orphan, which dangling pointers each surface can see |
| [cli/search.md](cli/search.md) | `search` | ranked retrieval over metadata and bodies — exact by default, the two engines and what the index silently loses, `@all` across bundles, the two JSON envelopes |
| [cli/map.md](cli/map.md) | `index` `dirs` | orientation: the §8 directory map and the cluster sizes, how `--dir`/`--depth`/ancestors compose, what a synthesized listing means, how not to page the bundle |
| [cli/views.md](cli/views.md) | `catalog` `files` `tags` `types` `stats` | the browser panels as text — per-concept metadata, the folder tree, tag and type rollups, bundle totals, and the JSON each emits |
| [cli/serve.md](cli/serve.md) | `server` `render` | the interactive page and its static twin — what renders, what is fetched live, many bundles behind one hub, the trust boundary both share |
| [cli/registry.md](cli/registry.md) | `registry` (`init` `set` `del` `default` `rename` `group` `ungroup` `list`) | naming bundles once: which file is written and how it is found, path-keyed vs slug-keyed verbs, groups, why the default is a position |
| [cli/graph.md](cli/graph.md) | `graph` | the raw node/edge dump and what it costs, plus the two rankings [refine](../playbooks/refine.md) reads — `--hubs` by concept, `--traffic` by directory |

A question that ends in *what does the spec actually say* leaves the CLI
entirely: [spec-map.md](spec-map.md) names the § and
[SPEC.md](SPEC.md) carries its words.

A verb `okf help` lists and no row here documents is an **extension's**, not a
gap in the docs — ask `okf <verb> --help`. A row whose file is missing is a note
to make, not a reason to stop: grep `reference/cli/` for the verb and proceed.
<!-- rule:okf-cli-index -->

## When it isn't installed

Don't probe for the tool before using it — just run the verb. A shell `okf:
command not found` is the only thing that means the gem isn't installed: say so
and stop (`gem install okf`, or from a checkout `cd gem && bundle exec rake
install`); never fabricate a result. Any line that starts `error:` is the CLI
*answering* — a bundle or usage result to read, not a missing toolchain.

## Invocation

The surface is self-describing — `okf --help` maps every verb, `okf <verb> --help`
its flags. Ask the tool for what exists; this file carries only what `--help`
cannot: each verb's semantics, its traps, and its JSON shape.

**The verb list is open, not closed.** An installed extension gem adds verbs of
its own, listed under `installed extensions:` in `okf help`. So a verb that
`--help` shows and this file does not document is **normal, not a documentation
error** — ask `okf <verb> --help` for it, and expect nothing here about its
semantics or JSON. Every file this index routes to documents the built-ins
only.

**`--json` is compact by design.** Every emitting verb prints single-line JSON —
the token-efficient substrate you consume; `--pretty` (which implies `--json`)
indents it for a human. The bytes differ, the JSON is identical, so parse either.
When you only need to *scan* a bundle, the plain text views are lighter still than
JSON (they print each key once, not per row) — reach for `--json` when you need to
extract structure, not merely read it.

**Project the JSON to what you'll read.** On `index`, `catalog`, and `files`,
`--fields a,b` keeps only those properties and `--except a,b` drops them
(mutually exclusive; both imply `--json`; an unknown name is a usage error that
lists the valid ones). Projection happens before emission, so you pay no tokens
for a field you dropped — e.g. `okf index <dir> --except body,listing` is the lean
directory *skeleton* (structure + rollups), and on a large bundle that is the
difference between a few hundred bytes and hundreds of KB, since the per-item rows
(`listing`) dominate at scale. `okf index --no-body` is shorthand for dropping just
`body`. <!-- rule:okf-project-json -->

**Every output names its bundle.** Two keys, one meaning each: `bundle` is
always a directory, `slug` always a registry slug. Name a bundle by `@slug` and
the answer comes back in that identity — `OKF lint — @handbook (/path/to/one)`,
and `{ "bundle": "/path/to/one", "slug": "handbook", … }` — so an agent holding
several bundles never has to remember which invocation produced which output.
A bundle named by path carries no `slug`: it may not have one, and inventing a
name it was never given would imply a registration that does not exist.

**@slug — point any verb at a registered bundle.** Wherever a `<dir>` goes,
`@slug` names a bundle registered via `okf registry set`, and bare `@` the
registry's default. They resolve through `$OKF_HOME` (default `~/.okf`) — the
single lever on which registry *any* verb reads, and it names exactly one, with
no fallback behind it. The slug is normalized as registration
normalized it — `@One` finds the bundle from dir `One` — but never to a
placeholder: `@***` names nothing, not a bundle. An unknown slug, a
registered-but-gone directory, or a malformed registry file is a usage error
(exit 2) whose message names the registry file consulted and the next move —
an explicit ask fails hard, never silently skipped. So `okf lint @handbook`
or `okf index @` work from any directory, no path recall needed.

**Exit codes:** `0` success · `1` non-conformant bundle (or a `lint --fail-on`
threshold crossed) · `2` usage error. `graph`, `server`, and `render` are best-effort
(§11): a file the reader cannot use — frontmatter that will not parse, or a file it
cannot open at all — is skipped and noted on stderr, never fatal. The note counts;
`validate` names each file and why.

**One bundle per verb, except two.** Only `search` merges several bundles and only
`server` mounts them; hand a second bundle to any other verb — two dirs, two refs,
or a mix — and it is a usage error (exit 2), never a silent answer about the first.
To ask the same question of several bundles, ask `search`, or ask each in turn.
<!-- rule:okf-one-bundle-per-verb -->

## The shared filters — `--type` `--dir` `--tag` `--status` `--trust`

The four list views of [cli/views.md](cli/views.md) narrow with the same
filters the browser panels offer —
`--type TYPE`, `--dir PATH`, `--tag TAG`, `--status STATUS`, `--trust TIER`
(`search` takes them too); each takes the ones orthogonal to itself (`tags`
can't filter by tag). `--status` matches the *effective* status (absent reads
`stable`, §5.4) and `--trust` the derived tier, either spelling
(`machine-confirmed` or `machine_confirmed`) — on a v0.1 bundle
`--status stable` and `--trust unverified` match everything, which is §13.1
reading, not an error, and an unknown value matches nothing at exit 0.
Matching is case-insensitive; `--type` and
`--tag` are exact, `--dir` takes the named directory **and everything below it**
(`--dir platform` reaches `platform/services/api`). A concept at the bundle root
lives in `.`, which `--dir` also accepts as plain `root` (no shell quoting) —
except in a bundle holding a real `root/` directory, where that directory takes
the name and `.` is the only spelling of the bundle root. A
filter that matches nothing is an empty view, not an error: `okf tags <dir> --dir
billing --json` answers "which tags does the billing cluster use?",
`okf catalog <dir> --tag auth` answers "what carries the auth tag?".

**`--area` is deprecated.** It still works — matching the *first path segment*
only, its old behavior unchanged — and prints `warning: --area is deprecated, use
--dir` on stderr (stdout stays clean, so a `--json` consumer is unaffected). Same
for `tags --by area`. Both go in a later release; write `--dir` in anything new.
On `index` it combines with neither `--depth` nor `--dir` — exit 2, because it is
*exact* and both of those select a range, so the pair used to return the area
plus whatever the other flag selected: an answer to neither question.
