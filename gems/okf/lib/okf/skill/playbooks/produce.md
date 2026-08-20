# Playbook: produce — create or extend a bundle

The craft that makes these steps land well — granularity, choosing `type`, tag
vocabulary, topology, links, sources — lives in
[authoring.md](../reference/authoring.md). Read it before a non-trivial produce.

1. Unsure of a rule? [spec-map.md](../reference/spec-map.md) names the § that
   settles it; read that section of [SPEC.md](../reference/SPEC.md).
2. Pick the source(s): **code** (derive concepts from source, READMEs, docstrings,
   config), **docs/wiki** (distill pages into concepts; record the originals in
   `sources:` and key claims with `[^id]` footnotes), **manual** (decisions,
   playbooks, metrics that live only in people's heads). If the source documents
   should survive as the concepts themselves — verbatim — that is
   [migrate.md](migrate.md), not produce.
3. Choose a domain-based directory layout. One concept per file.
4. Write each concept from [templates/concept.md](../templates/concept.md) — or
   [templates/attested-computation.md](../templates/attested-computation.md)
   when the concept *is* a sanctioned computation (§10): a descriptive `type`
   from the bundle's vocabulary, recommended fields filled, cross-links to
   related concepts written into prose. `generated.by` says who produced the
   content, in §7's spelling — and when a tool writes a concept unattended, the
   tool writes **its own** identity, `<producer>/<version>`: `human:<maintainer>`
   from a generator would be a fabricated human attestation, the exact false
   provenance §5 exists to prevent.
5. Add or refresh `index.md` per directory from
   [templates/index.md](../templates/index.md); for the bundle root use
   [templates/root-index.md](../templates/root-index.md) so it carries
   `okf_version: "0.2"`. Append a dated entry to `log.md`.
6. **Close out** — walk the
   [Closeout gate](../reference/authoring.md#closeout--the-finishing-gate)
   (`validate` + `lint` are part of it, see
   [cli/checks.md](../reference/cli/checks.md))
   before finishing.
