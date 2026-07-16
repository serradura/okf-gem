# Playbook: produce — create or extend a bundle

The craft that makes these steps land well — granularity, choosing `type`, tag
vocabulary, topology, links, citations — lives in
[authoring.md](../reference/authoring.md). Read it before a non-trivial produce.

1. Read [SPEC.md](../reference/SPEC.md) if you are unsure of any rule.
2. Pick the source(s): **code** (derive concepts from source, READMEs, docstrings,
   config), **docs/wiki** (distill pages into concepts; cite the originals under
   `# Citations`), **manual** (decisions, playbooks, metrics that live only in
   people's heads). If the source documents should survive as the concepts
   themselves — verbatim — that is [migrate.md](migrate.md), not produce.
3. Choose a domain-based directory layout. One concept per file.
4. Write each concept from [templates/concept.md](../templates/concept.md): a
   descriptive `type` from the bundle's vocabulary, recommended fields filled,
   cross-links to related concepts written into prose.
5. Add or refresh `index.md` per directory from
   [templates/index.md](../templates/index.md); for the bundle root use
   [templates/root-index.md](../templates/root-index.md) so it carries
   `okf_version: "0.1"`. Append a dated entry to `log.md`.
6. **Close out** — walk the
   [Closeout gate](../reference/authoring.md#closeout--the-finishing-gate)
   (`validate` + `lint` are part of it, see [cli.md](../reference/cli.md))
   before finishing.
