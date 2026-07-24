# Authoring OKF well — the craft

The spec ([SPEC.md](SPEC.md)) tells you what is *legal*. This file is what is
*good* — the modelling judgment that turns a pile of conformant files into
knowledge worth consuming. Read it before `produce` or `maintain`, and keep the §9
conformance rules in mind (parseable frontmatter, a non-empty `type`, and
well-formed reserved files — the hard rules in [SKILL.md](../SKILL.md)); everything
else is guidance a consumer must tolerate.

## What each SPEC section governs

Consult the right section on demand instead of re-reading all of [SPEC.md](SPEC.md):

| § | Governs | Reach for it when |
|---|---------|-------------------|
| §3 | bundle structure, reserved filenames | laying out directories |
| §4 | concept documents & frontmatter | writing or validating a concept |
| §5 / §5.3 | cross-links; **broken links are tolerated** | linking; judging a "broken" link |
| §6 | index files & progressive disclosure | orienting; writing or synthesizing an index |
| §7 | log files | recording history |
| §8 | citations & provenance | any external or empirical claim |
| §9 | conformance — the hard gate | what `validate` may and may not reject |
| §11 | versioning (`okf_version`) | the root index's one allowed field |

## Modelling principles

These are the decisions that make or break a bundle. None are enforced by the
tools — they are yours to get right.

### One concept = one file — but what is a concept? <!-- rule:okf-atomic-concept -->
A concept is the smallest unit of knowledge someone would want to **link to or
cite on its own**. If two things are always referenced together, they are one
concept; if either is referenced alone, split them. Err atomic — it is cheap to
link two files and expensive to untangle one that grew two identities. Signs a
file should split: two `type`s fighting for the frontmatter, two audiences, or a
heading that others would plausibly link to directly. The file path (minus `.md`)
is the concept's stable ID, so name it for what it *is*, not where it sits today.

### `type` is the graph's vocabulary <!-- rule:okf-type-vocabulary -->
`type` is the only required field, and it is the dimension every consumer groups
and colours by (the graph server colours nodes by it; graph analysis clusters by
it). It is freeform — the spec does not enumerate types — and that freedom is a
responsibility. Keep a **small, consistent, descriptive** vocabulary per bundle
(`Service`, `Dataset`, `Metric`, `Decision`, `Playbook`, `Runbook`, …). Reusing
types across files is what makes the graph legible; inventing a new type per file
makes `type` meaningless. Before adding a new type, check what the bundle already
uses.

### Tags are the connective axis — curate them like a vocabulary <!-- rule:okf-tag-vocabulary -->
`type` says what a concept *is*; the directory says where it *lives*; `tags` are
the only axis that cuts across both. A tag earns its place one of two ways: by
**connecting** concepts that type and area don't already group (a `billing` tag
spanning a service, a dataset, and a decision), or by **marking** something worth
flagging even on one concept (`security`, `deprecated`). A tag that merely
restates the concept's own type, area, or title adds no edge — it is noise wearing
a tag's clothes. Reuse before minting: run `okf tags <dir>` and pick from the
existing vocabulary first; 2–4 tags per concept is plenty. Scattered singletons
are how a vocabulary rots into one label per file.

### Topology: organize by domain, not by type <!-- rule:okf-domain-topology -->
Lay out directories by what the knowledge is *about* (`services/`, `datasets/`,
`decisions/`), not by concept type. The directory tree is itself knowledge — it
shows a reader how the system decomposes, and it usually mirrors the shape of the
codebase or the org. A `types/`-first layout scatters related concepts and buries
the domain.

### `resource` is the bridge to reality <!-- rule:okf-resource-bridge -->
Set `resource` (a canonical URI) **only** when a concept *is* a real, addressable
asset — a table (`bigquery://…`), a service repo, a dashboard, an endpoint. Its
presence is what lets `maintain` find every concept affected by a changed asset in
one `okf search <dir> <uri>` call. Abstract concepts — a decision, a principle, a metric
definition — have no resource, and **omitting it is meaningful**, not laziness. Do
not invent placeholder URIs.

### Links are untyped on purpose <!-- rule:okf-untyped-links -->
A markdown link asserts only "these two relate." The *kind* of relationship —
depends-on, supersedes, derived-from, owns — lives in the **prose around the
link**, never in a made-up typed-edge syntax. Write the sentence that explains the
relationship and put the link inside it. Prefer absolute bundle-relative targets
(`/services/auth-api.md`) so links survive file moves. A link to a concept that
does not exist yet is fine — it is not-yet-written knowledge (§5.3), and `lint`'s
backlog will surface it as demand.

### Provenance is what makes knowledge trustworthy (§8) <!-- check:uncited_external -->
Any external or empirical claim — a latency number, an approval, a quota, a
"because X team decided Y" — should carry a citation to its source under a
`# Citations` heading. Uncited claims are exactly how a bundle decays into folklore
nobody trusts. `lint`'s provenance category exists to catch missing and broken
citations; write them as you go so you never have to reconstruct them.

### Capture the non-obvious — not what code already says <!-- rule:okf-non-obvious -->
A bundle that restates function signatures or config keys goes stale the moment
the code changes and adds no knowledge. Capture what you **cannot** derive by
reading one source file: the *why* behind a design, cross-cutting relationships,
decisions and their tradeoffs, operational tribal knowledge, the metric that
actually matters. If the code or git history already records it faithfully, link
to it rather than duplicating it.

### Write for both readers at once <!-- rule:okf-dual-audience -->
Use structural markdown so an agent can extract deterministically and a human can
skim: headings, tables, fenced code, lists. Conventional headings a reader expects
are `# Schema` (field/column tables), `# Examples`, and `# Citations`. Fill
recommended frontmatter — `title`, `description`, `tags`, `timestamp` (ISO 8601) —
whenever it aids consumption.

### Reserved files <!-- rule:okf-reserved-files -->
`index.md` is a directory listing and carries **no frontmatter** — with one
exception: the **bundle-root** `index.md` is the only index that may carry
frontmatter, and it may carry *only* `okf_version: "0.1"` (§11; `validate` §9.3
flags any other key there). `log.md` is an ISO-dated change history, newest first.
Never use these names for concepts. Templates:
[concept](../templates/concept.md), nested [index](../templates/index.md),
bundle-root [root-index](../templates/root-index.md), [log](../templates/log.md).

## Playbooks

The step-by-step playbooks live in [../playbooks/](../playbooks/), one file per
verb (search, produce, migrate, maintain, consume, curate, doctor), routed by the
Commands table in [SKILL.md](../SKILL.md). The Closeout below is their shared
finishing gate.

## Closeout — the finishing gate

`produce` step 6 and `maintain` steps 4–7 both land here: before calling an
authoring task done, walk this once. It is the repo's "turn every task into a check
that can fail" discipline, and followed literally it catches the enumeration drift
grep can't:

- **Index enumerations** — every `index.md` that lists what you added, renamed, or
  removed is updated; re-run `okf index` and eyeball each listing against reality.
  Easy to skip, expensive to miss — this is the check that was missing.
- **`log.md`** — a dated entry, newest first.
- **Timestamps** bumped on the concepts you touched.
- **`validate`** — zero §9 errors.
- **`lint`** — cheap findings cleared; pass `--stale-after` when concepts carry
  timestamps (freshness is off by default).
- **`loose` review + tag curation** — the two semantic passes (maintain steps 6–7);
  worth a pass in `produce` too on a non-trivial bundle.
