---
description: Search the bundle, set up and doctor it, run the curation cycle, or hand any task to the OKF skill
argument-hint: "[search|maintain|curate|produce|consume|doctor|<okf-cli-verb>] [dir] [--flags]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

Route on the arguments ("$ARGUMENTS"), then use the okf skill that ships with
this plugin:

- Empty: read the skill's `playbooks/menu.md` and follow it exactly as written.
  Orient on the CLI, the bundle, and what `validate`/`lint` report, then
  recommend the two or three highest-value moves and let the user pick. Never
  auto-run a workflow. (No CLI yet? `menu.md` sends you to `doctor.md` to set up.)
- `search <query…>`: read the skill's `playbooks/search.md` and follow it
  exactly as written. Retrieval is progressive disclosure: ingest the map
  (`okf index`), decide where to look, cut across with `okf search`, and read
  only the winning bodies — never dump the bundle for context.
- `doctor [dir]`: read the skill's `playbooks/doctor.md` and follow it exactly
  as written (install and verify the CLI, then doctor the bundle).
- `curate [dir]`: read the skill's `playbooks/curate.md` and follow it exactly
  as written. Curation is structural upkeep of the bundle as it stands
  (validate + lint + loose); nothing in the project needs to have changed.
- Anything else (produce, maintain, consume, an okf CLI verb, or a free-form
  task): invoke the skill with the arguments unchanged; the skill owns the
  judgment. `maintain` is the one to reach for when the code or docs changed
  and the bundle's content must catch up with reality.
