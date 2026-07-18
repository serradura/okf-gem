# Playbook: maintain — keep a bundle in sync with reality

Reach for this when the project changed and the bundle's *content* must catch
up. The modelling craft behind steps 3 and 7 lives in
[authoring.md](../reference/authoring.md).

1. **Orient before hunting.** Run `okf index <dir>` (the §6 map — every directory's
   index body, rollups, and listings), read `log.md` (the §7 baseline: what changed
   last), and `okf stats <dir>` (size and shape) *before* you grep. It is the
   cheapest context and it primes the hunt — and it is the only reliable way to
   catch enumeration drift, because **grep cannot find an index entry that is
   missing.** (This is the always-on reflex in [SKILL.md](../SKILL.md).)
2. **Find *every* affected concept** — the failure mode is fixing only the obvious
   one. Don't rely on reading the whole bundle; that only scales on tiny ones. Run
   `okf search <dir> <resource-URI-or-name>` — it hits frontmatter *and* bodies and
   returns ranked concept ids, not line noise; grep is the backstop for what search
   cannot express — and `okf graph <dir> --json --minimal` to pull the edges (the
   concepts that link *to* the ones you're touching) without paying for every body.
   Let search and the graph find them so nothing drifts silently.
3. Update bodies and `timestamp`; fix or add cross-links; create new concepts for
   new assets; mark retired assets with a `**Deprecation**` note rather than
   silently deleting the context that explains them.
4. **Update every enumeration that names what you changed — including `index.md`
   bodies**, not just the concept files: a new, renamed, or removed concept changes
   its directory's index listing too. Append a dated `log.md` entry. Step 1's map
   is how you verify this — re-run `okf index` and confirm each listing matches
   reality.
5. Run `validate`, then `lint` to catch the curation drift the change introduced —
   new orphans, broken citations, dangling index entries. Add `--stale-after`
   (e.g. `90d`) if concepts carry timestamps: freshness is off by default, so a
   plain `lint` will not tell you what the change left stale.
6. **Review loose files** <!-- check:unlinked --> — run `okf loose <dir>` (the
   folder-grouped view of `lint`'s `unlinked` check): the concepts with **no
   cross-links in or out**, which
   float in the graph. This is a semantic pass the tool cannot do for you — for each
   floater, judge intent:
   - **should it link out?** the concept relates to others but says so nowhere —
     write the sentence that explains the relationship and put the link in it;
   - **should something link to it?** it is knowledge others should reach by
     following links, not just via an index — add the inbound link from where it
     belongs;
   - **legitimately terminal?** a backlog item, a spec reference, a leaf reachable
     by design only through its index — leave it. **Terminal-by-design is not a
     defect.** Loose ≠ orphan: an index listing makes a file *reachable* (not an
     orphan) but is not a graph edge, so an indexed file can still float here.
7. **Curate the tag vocabulary** when the pass
   touched tags, or when `okf tags <dir>` shows a long tail of singletons. Run `okf tags <dir> --by area` and
   `--by type` — the grouped view is the analysis; read each group top-down:
   - **twins** — two tags riding the exact same concepts (equal counts sort them
     adjacent). Merge into one unless each genuinely names a different theme.
   - **group-name echoes** — a tag matching its own group's name (a `format` tag
     inside `format/`, an `overview` tag on an Overview). It restates an axis the
     concept already carries; drop it from those concepts.
   - **singletons** — for each, ask: would an existing tag serve? is it an
     anticipated cluster that concepts landing soon will join? is it a deliberate
     marker (`security`, `deprecated`)? Merge, keep, or drop accordingly — a
     count of 1 is a question, never a verdict.
   - **connective tags** — recurring across groups: these are the vocabulary's
     spine. Protect them; prefer merging others *into* them over renaming them,
     because consumers learn these keys and stability is part of their value.
   The trap in this pass is optimizing the numbers instead of the vocabulary:
   you can reach zero singletons by deleting every tag, and perfect cohesion by
   tagging everything alike. The goal is a small set of tags where each one
   either connects or marks — judged, not counted.

Before calling the pass done, walk the
[Closeout gate](../reference/authoring.md#closeout--the-finishing-gate) once:
steps 4–7 above cover most of it, and the gate is the check that nothing was
skipped.
