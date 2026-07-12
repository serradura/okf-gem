# Playbook: curate an OKF bundle

Run the complete curation cycle over the whole bundle and act on the findings
with the okf skill's judgment. If the `okf` CLI is missing, stop and follow
[doctor.md](doctor.md) first (in Claude Code: `/okf:gem doctor`).

Curation is structural upkeep of the bundle *as it stands*: conformance,
reachability, backlog, completeness, hygiene. It is not `maintain`, the
skill's workflow for when the project changed and the bundle's *content*
must catch up with reality; reach for that one when what is written stopped
being true. Curating can surface semantic staleness, and when it does,
switch to `maintain` for those concepts.

1. Locate the bundle: the directory you were given, if any; otherwise a
   `.okf/` directory or a root `index.md` whose frontmatter carries
   `okf_version`.
2. Measure: `okf validate <root> --json`, `okf lint <root> --json`,
   `okf loose <root> --json`.
3. Interpret through the three lenses the okf skill teaches, and keep them
   separate:
   - conformance errors (§9) are the only hard failures; fix them first,
     always;
   - lint findings are curation debt across reachability, backlog,
     completeness, freshness, provenance, and hygiene. They are advisory;
     rank them by how much each hurts a reader navigating the graph;
   - loose files can be legitimate terminal leaves, so judge each one before
     linking it anywhere.
4. Propose, then apply: list the fixes worth making (must-fix errors first,
   then the debt worth settling, then the judgment calls), apply the ones the
   user confirms, or all the obvious ones when the user asked you to just
   clean up.
5. Re-measure: run validate + lint again and report the before and after in
   two lines.
