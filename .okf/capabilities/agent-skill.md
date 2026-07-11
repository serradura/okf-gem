---
type: Capability
title: Companion agent skill (skill)
description: A SKILL.md plus references and templates, shipped inside the gem, that teaches an agent to author OKF.
resource: lib/okf/skill.rb
tags: [skill, agent, install]
timestamp: 2026-07-11T12:00:00Z
---

# Overview

The gem carries the **OKF agent skill** — a `SKILL.md` with reference and
template files that teach a coding agent to *produce*, *maintain*, and *consume*
[OKF](../format/okf-format.md) bundles and to drive the [CLI](../cli.md). The
authoring judgment the executable can't encode lives here; the executable handles
the mechanics.

# `okf skill <dest>` installs it

`OKF::Skill.install` copies the skill into a destination you name — Claude Code's
`.claude/skills/okf`, an agent-agnostic `.agents/skills/okf`, wherever your agent
looks. The rules are deliberate:

- the **destination is required** — no magic default — so a user always decides
  where the skill lands;
- the destination must be **empty unless `--force`**, so a customized skill is
  never clobbered.

# One canonical copy, versioned with the gem

The skill ships **only** from `lib/okf/skill/**` — that tree is the single source,
and `install` copies from it. Because the skill rides inside the gem, installing
the gem already puts the skill on the machine, and the skill's CLI reference can
**never drift** from the executable it was released with. Local installs
elsewhere are gitignored so they never masquerade as the source.

# Citations

[1] [lib/okf/skill.rb](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill.rb) — the installer.
[2] [lib/okf/skill/SKILL.md](https://github.com/serradura/okf-gem/blob/main/lib/okf/skill/SKILL.md) — the skill itself.
