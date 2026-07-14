---
type: Capability
title: Companion agent skill (skill)
description: A SKILL.md plus references and templates, shipped inside the gem, that teaches an agent to author OKF.
resource: lib/okf/skill.rb
tags: [agent, install]
timestamp: 2026-07-13T12:00:00Z
---

# Overview

The gem carries the **OKF agent skill** — a `SKILL.md` with reference and
template files that teach a coding agent to *produce*, *maintain*, *consume*,
and *search* [OKF](../format/okf-format.md) bundles and to drive the
[CLI](../cli.md). The authoring judgment the executable can't encode lives here;
the executable handles the mechanics. Each verb routes to its own playbook
(`playbooks/`); the search playbook is progressive disclosure end to end —
ingest the index map, decide where to look, cut across with
[`okf search`](search.md), read only the winning bodies — and pointed questions
route to it first from the menu and consume playbooks.

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

The skill ships **only** from `lib/okf/skill/**` — that tree is the single source,
and `install` copies from it. Because the skill rides inside the gem, installing
the gem already puts the skill on the machine, and the skill's CLI reference can
**never drift** from the executable it was released with. Local installs
elsewhere are gitignored so they never masquerade as the source.

# A second channel: the Claude Code plugin

The repository doubles as a plugin marketplace, and the plugin carries a
**generated** copy of the same skill (`plugin/skills/okf`) — `rake plugin:sync`
regenerates it after any skill edit or version bump, and a test fails the build
on drift, so the canonical-copy rule survives the second channel. Around the
skill the plugin adds a front-door command (`/okf:gem`, listing `search` first)
and a PostToolUse hook that runs `okf validate` + `okf lint` after every edit
inside a bundle and hands the relevant findings back as context. Nothing under
`plugin/` ships in the gem.

# Citations

[1] [lib/okf/skill.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill.rb) — the installer.
[2] [lib/okf/skill/SKILL.md](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/SKILL.md) — the skill itself.
[3] [test/plugin/sync_test.rb](https://github.com/serradura/okf-gem/blob/main/test/plugin/sync_test.rb) — the drift check on the plugin's generated copy.
