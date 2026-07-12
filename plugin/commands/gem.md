---
description: Set up and doctor the bundle, run the curation cycle, or hand any task to the OKF skill
argument-hint: "[maintain|curate|produce|consume|doctor|<okf-cli-verb>] [dir] [--flags]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

Route on the arguments ("$ARGUMENTS"), then use the okf skill that ships with
this plugin:

- Empty, or `doctor [dir]`: read the skill's `playbooks/doctor.md` and follow
  it exactly as written (install and verify the CLI, then doctor the bundle).
- `curate [dir]`: read the skill's `playbooks/curate.md` and follow it exactly
  as written. Curation is structural upkeep of the bundle as it stands
  (validate + lint + loose); nothing in the project needs to have changed.
- Anything else (produce, maintain, consume, an okf CLI verb, or a free-form
  task): invoke the skill with the arguments unchanged; the skill owns the
  judgment. `maintain` is the one to reach for when the code or docs changed
  and the bundle's content must catch up with reality.
