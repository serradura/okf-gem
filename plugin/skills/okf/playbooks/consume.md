# Playbook: consume — use a bundle as context

1. **Orient first** (the [SKILL.md](../SKILL.md) reflex): `okf index <dir|@slug>` maps
   the whole bundle in one pass — every directory's index body, rollups, and listings —
   and `log.md` gives recent history. Address a registered bundle by `@slug` (bare
   `@` = the default); if the cwd carries no bundle, `okf registry list` finds one
   instead of a directory hunt. Then follow links only into the concepts the
   task needs. For a *pointed question* rather than broad context, switch to the
   [search playbook](search.md): map → finder (`okf search`) → only the winning
   bodies. For a large bundle, `okf graph --json --minimal` gives the whole link
   structure at once so you can plan a traversal without opening every file.
2. Treat broken links as not-yet-written knowledge, not errors.
3. **Write-back reflex:** if you learn something durable while working — a fact the
   bundle lacks, a link it is missing, a concept that no longer matches reality —
   switch to [maintain](maintain.md) and record it. That reflex is what keeps the
   bundle alive.
