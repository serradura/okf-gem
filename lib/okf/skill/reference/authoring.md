# Authoring OKF well — the craft

The spec ([SPEC.md](SPEC.md)) tells you what is *legal*. This file is what is
*good* — the modelling judgment that turns a pile of conformant files into
knowledge worth consuming. Read it before `produce` or `maintain`, and keep the §9
conformance rules in mind (parseable frontmatter, a non-empty `type`, and
well-formed reserved files — the hard rules in [SKILL.md](../SKILL.md)); everything
else is guidance a consumer must tolerate.

## Modelling principles

These are the decisions that make or break a bundle. None are enforced by the
tools — they are yours to get right.

### One concept = one file — but what is a concept?
A concept is the smallest unit of knowledge someone would want to **link to or
cite on its own**. If two things are always referenced together, they are one
concept; if either is referenced alone, split them. Err atomic — it is cheap to
link two files and expensive to untangle one that grew two identities. Signs a
file should split: two `type`s fighting for the frontmatter, two audiences, or a
heading that others would plausibly link to directly. The file path (minus `.md`)
is the concept's stable ID, so name it for what it *is*, not where it sits today.

### `type` is the graph's vocabulary
`type` is the only required field, and it is the dimension every consumer groups
and colours by (the graph server colours nodes by it; graph analysis clusters by
it). It is freeform — the spec does not enumerate types — and that freedom is a
responsibility. Keep a **small, consistent, descriptive** vocabulary per bundle
(`Service`, `Dataset`, `Metric`, `Decision`, `Playbook`, `Runbook`, …). Reusing
types across files is what makes the graph legible; inventing a new type per file
makes `type` meaningless. Before adding a new type, check what the bundle already
uses.

### Topology: organize by domain, not by type
Lay out directories by what the knowledge is *about* (`services/`, `datasets/`,
`decisions/`), not by concept type. The directory tree is itself knowledge — it
shows a reader how the system decomposes, and it usually mirrors the shape of the
codebase or the org. A `types/`-first layout scatters related concepts and buries
the domain.

### `resource` is the bridge to reality
Set `resource` (a canonical URI) **only** when a concept *is* a real, addressable
asset — a table (`bigquery://…`), a service repo, a dashboard, an endpoint. Its
presence is what lets `maintain` find every concept affected by a changed asset by
grepping for that URI. Abstract concepts — a decision, a principle, a metric
definition — have no resource, and **omitting it is meaningful**, not laziness. Do
not invent placeholder URIs.

### Links are untyped on purpose
A markdown link asserts only "these two relate." The *kind* of relationship —
depends-on, supersedes, derived-from, owns — lives in the **prose around the
link**, never in a made-up typed-edge syntax. Write the sentence that explains the
relationship and put the link inside it. Prefer absolute bundle-relative targets
(`/services/auth-api.md`) so links survive file moves. A link to a concept that
does not exist yet is fine — it is not-yet-written knowledge (§5.3), and `lint`'s
backlog will surface it as demand.

### Provenance is what makes knowledge trustworthy (§8)
Any external or empirical claim — a latency number, an approval, a quota, a
"because X team decided Y" — should carry a citation to its source under a
`# Citations` heading. Uncited claims are exactly how a bundle decays into folklore
nobody trusts. `lint`'s provenance category exists to catch missing and broken
citations; write them as you go so you never have to reconstruct them.

### Capture the non-obvious — not what code already says
A bundle that restates function signatures or config keys goes stale the moment
the code changes and adds no knowledge. Capture what you **cannot** derive by
reading one source file: the *why* behind a design, cross-cutting relationships,
decisions and their tradeoffs, operational tribal knowledge, the metric that
actually matters. If the code or git history already records it faithfully, link
to it rather than duplicating it.

### Write for both readers at once
Use structural markdown so an agent can extract deterministically and a human can
skim: headings, tables, fenced code, lists. Conventional headings a reader expects
are `# Schema` (field/column tables), `# Examples`, and `# Citations`. Fill
recommended frontmatter — `title`, `description`, `tags`, `timestamp` (ISO 8601) —
whenever it aids consumption.

### Reserved files
`index.md` is a directory listing and carries **no frontmatter** — with one
exception: the **bundle-root** `index.md` is the only index that may carry
frontmatter, and it may carry *only* `okf_version: "0.1"` (§11; `validate` §9.3
flags any other key there). `log.md` is an ISO-dated change history, newest first.
Never use these names for concepts. Templates:
[concept](../templates/concept.md), nested [index](../templates/index.md),
bundle-root [root-index](../templates/root-index.md), [log](../templates/log.md).

## Playbooks

### produce — create or extend a bundle
1. Read [SPEC.md](SPEC.md) if you are unsure of any rule.
2. Pick the source(s): **code** (derive concepts from source, READMEs, docstrings,
   config), **docs/wiki** (distill pages into concepts; cite the originals under
   `# Citations`), **manual** (decisions, playbooks, metrics that live only in
   people's heads).
3. Choose a domain-based directory layout. One concept per file.
4. Write each concept from [templates/concept.md](../templates/concept.md): a
   descriptive `type` from the bundle's vocabulary, recommended fields filled,
   cross-links to related concepts written into prose.
5. Add or refresh `index.md` per directory from
   [templates/index.md](../templates/index.md); for the bundle root use
   [templates/root-index.md](../templates/root-index.md) so it carries
   `okf_version: "0.1"`. Append a dated entry to `log.md`.
6. Run `validate` and fix every error before finishing; run `lint` and clear the
   cheap findings (see [cli.md](cli.md)).

### maintain — keep a bundle in sync with reality
1. Find *every* affected concept — the failure mode is fixing only the obvious one.
   Don't rely on reading the whole bundle; that only scales on tiny ones. Grep the
   changed asset's `resource` URI across the bundle, grep its path/name, and use
   `okf graph --json` to pull the concepts that link *to* the ones you're touching.
   Let grep and the graph find them so nothing drifts silently.
2. Update bodies and `timestamp`; fix or add cross-links; create new concepts for
   new assets; mark retired assets with a `**Deprecation**` note rather than
   silently deleting the context that explains them.
3. Update the relevant `index.md` files and append a dated `log.md` entry.
4. Run `validate`, then `lint` to catch the curation drift the change introduced —
   new orphans, broken citations, dangling index entries. Add `--stale-after`
   (e.g. `90d`) if concepts carry timestamps: freshness is off by default, so a
   plain `lint` will not tell you what the change left stale.
5. **Review loose files** — run `okf loose <dir>` (the folder-grouped view of
   `lint`'s `unlinked` check): the concepts with **no cross-links in or out**, which
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

### consume — use a bundle as context
1. Read the bundle-root `index.md` first for progressive disclosure, then follow
   links only into the concepts the task needs. For a large bundle, `okf graph
   --json` gives you the whole link structure at once so you can plan a traversal.
2. Treat broken links as not-yet-written knowledge, not errors.
3. **Write-back reflex:** if you learn something durable while working — a fact the
   bundle lacks, a link it is missing, a concept that no longer matches reality —
   switch to `maintain` and record it. That reflex is what keeps the bundle alive.
