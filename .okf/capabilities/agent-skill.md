---
type: Capability
title: Companion agent skill (skill)
description: A SKILL.md plus references and templates, shipped inside the gem, that teaches an agent to author OKF.
resource: gems/okf/lib/okf/skill.rb
tags: [agent, install]
generated:
  by: human:maintainer
  at: 2026-08-17T12:00:00Z
sources:
  - title: gems/okf/lib/okf/skill.rb
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/lib/okf/skill.rb
  - title: gems/okf/lib/okf/skill/SKILL.md
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/lib/okf/skill/SKILL.md
  - title: gems/okf/test/plugin/sync_test.rb
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf/test/plugin/sync_test.rb
---

# Overview

The gem carries the **OKF agent skill** — a `SKILL.md` with reference and
template files that teach a coding agent to *produce*, *migrate*, *maintain*,
*refine*, *consume*, *search*, *curate*, and *doctor* [OKF](../format/okf-format.md) bundles
and to drive the [CLI](../cli.md). The authoring judgment the executable can't encode lives here;
the executable handles the mechanics. Each verb routes to its own playbook
(`playbooks/`); the search playbook is progressive disclosure end to end —
ingest the index map, decide where to look, cut across with
[`okf search`](search.md), read only the winning bodies — and pointed questions
route to it first from the menu and consume playbooks. The two authoring
on-ramps stay distinct: `produce` distills sources into new concepts, while
`migrate` adopts existing documentation in place — frontmatter and reserved
files added, bodies kept **verbatim**, with `okf validate --json` as the
worklist — so a document survives conversion recognizably itself. Three more verbs
bound that loop rather than drive it: `curate` is structural upkeep as the bundle
*stands* — `validate` + `lint` + `loose` — and hands off to `maintain` the moment
the finding is that the *content*, not the structure, has drifted; `refine` is the
inverse hand-off — the content is right but the *shape* underserves retrieval —
and restructures for cohesion over the evidence the [read views](read-views.md)
compute (tag locality via `tags --by`, the hub origin test via `graph --hubs`),
always proposing before it applies; `doctor` is the
one playbook that assumes nothing, installing and verifying the [CLI](../cli.md)
before it examines the bundle. A no-argument run is a verb of its own — the menu
reads the signals and names the highest-value move without running one.

**Every playbook names the same first move**, and that took a correction. The
skill had prescribed one in seven places — bare `okf index`, `index --no-body`,
`dirs --depth 1` — across SKILL.md, four playbooks and the CLI reference, and
that disagreement *is* the deliberation an agent pays for on every retrieval. A
lookup table added to SKILL.md to pre-decide it made things worse: it duplicated
guidance already in the reference, contradicted the file it sat in, and carried
payload figures measured on one private bundle. It was reverted for the
subtraction it should have been. Every site now says `okf dirs` first, then
`okf index --dir <branch>` to descend — chosen structurally, because `dirs` emits
one row per directory where `index` emits one per concept even under `--no-body`,
so the two scale with different things. The reason is in the skill; the numbers
are not.

# `okf skill <dest>` installs it

`OKF::Skill.install` copies the skill into a destination you name — Claude Code's
`.claude`, an agent-agnostic `.agents`, wherever your agent looks. The rules are
deliberate:

- the **destination is required** — no magic default — so a user always decides
  where the skill lands;
- it lands in a **`skills/okf/` folder** by default (`.claude` →
  `.claude/skills/okf`), because an agent discovers a skill as
  `<skills-dir>/<name>/SKILL.md` — so the skill settles in its own folder, not
  loose among the others. A `<dest>` already ending in `skills` only gains the
  `okf/` leaf; one already named `okf` is used as-is (idempotent); `--here`
  pastes straight into `<dest>`, wherever it is;
- the resolved directory must be **empty unless `--force`**, so a customized
  skill is never clobbered.

# One canonical copy, versioned with the gem

The skill ships **only** from `okf/lib/okf/skill/**` — that tree is the single source,
and `install` copies from it. Because the skill rides inside the gem, installing
the gem already puts the skill on the machine, and the skill's CLI reference can
**never drift** from the executable it was released with. Local installs
elsewhere are gitignored so they never masquerade as the source.

# Two more channels: the Claude Code plugin, and `skills/`

The repository doubles as a plugin marketplace, and the plugin carries a
**generated** copy of the same skill (`plugin/skills/okf`) — `rake skill:sync`
regenerates it after any skill edit or version bump, and a test fails the build
on drift, so the canonical-copy rule survives the second channel. Around the
skill the plugin adds a front-door command (`/okf:gem`) that is deliberately a
**pass-through shim**: it hands its arguments to the skill unchanged, so
`SKILL.md` stays the single router for every channel — the Commands table, the
intent inference, and the not-a-bundle `migrate` suggestion live only there,
where the drift test guards them, instead of in a second copy the test never
sees. The plugin also carries a PostToolUse hook that runs `okf validate` +
`okf lint` after every edit inside a bundle and hands the relevant findings
back as context. Nothing under `plugin/` ships in the gem.

The third channel is the generic one. A skill installer walks a repository's
`skills/` directory, so `skills/okf` is the same generated copy under the name
every such tool already looks for — `npx skills add serradura/okf-gem` installs
it into any of the agents that tool supports, no gem and no Claude Code
required. It costs one line in `GENERATED_SKILL_COPIES` rather than a second
task, which is the point: **one canonical tree with N destinations is one
obligation, and a second task to remember is a second task to forget.** The
guard scales with it — `rake skill:verify` compares file lists and SHA-256
checksums for every destination and `build` depends on it, so a copy cannot be
released stale, whatever channel it feeds.

The channels are not equivalent, and the difference is the version they carry.
The gem's copy is the release's, pinned to the executable beside it; the plugin's
follows the marketplace; `skills/` tracks this repository's default branch. A
consumer who needs the skill and the CLI to agree should take the gem's.
