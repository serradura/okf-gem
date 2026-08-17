# Authoring OKF well — the craft

The spec ([SPEC.md](SPEC.md)) tells you what is *legal*, and
[spec-map.md](spec-map.md) says which § settles which question. This file is
what is *good* — the modelling judgment that turns a pile of conformant files into
knowledge worth consuming. Read it before `produce` or `maintain`, and keep the
§11 conformance rules in mind (parseable frontmatter, a non-empty `type`, and
well-formed reserved files — the hard rules in [SKILL.md](../SKILL.md));
everything else is guidance a consumer must tolerate.

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
uses. One type the spec *does* name: `Attested Computation` (§10) is a contract,
not a suggestion — use it exactly when the concept carries a sanctioned
computation, and use the exact spelling.

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
the domain. Non-concept assets a concept points at — run instructions, attester
code, computation files — live under `references/` by convention (§6.3): a naming
convention, not a requirement, and the tools never require it.

### Hidden files are outside the bundle <!-- rule:okf-no-hidden-concepts -->
The reader excludes dot-prefixed files and every path under a dot-prefixed
directory — the Unix hidden-file convention, kept deliberately: a project root
often carries an installed skill (`.claude/`), templates (`.github/`) or other
markdown that is not knowledge, and reading a directory must not pull those in
as concepts. §3's taxonomy is read as covering the visible tree. The practical
rule: never author a concept under a hidden directory — no verb will ever see
it, and nothing will warn you.

### A path-valued field pointing at `references/` needs its leading `/` <!-- check:broken_attestation_ref -->
§6.2 gives `resource`, `sources[].resource`, `computation`, `executor.resource`
and `attester.resource` the same three forms as a link: a URL, a bundle-relative
path **beginning with `/`**, or a path relative to the concept. So a concept at
`metrics/revenue.md` writing `attester: { resource: references/attesters/rev.py }`
is naming `metrics/references/attesters/rev.py`, not the bundle's `references/`
tree — the trap being that §6.3's own example, and the SPEC's Appendix, spell
these paths bare from a nested concept. Write `/references/…` and the field
resolves from the bundle root wherever the concept sits, which is the same reason
[links](#links-are-untyped-on-purpose) prefer the absolute form. `lint` catches
the `.md` cases (`broken_attestation_ref`, `broken_source`); a `.sql` or `.py`
target is not a concept, so no lint check sees it — `okf references` is the
surface that does: it lists the `references/` tree from disk with every pointer
that misses, and names the leading-`/` fix when that is the miss.

### A frontmatter `id` renames the concept, not its home <!-- rule:okf-id-extension -->
§2 defines the Concept ID as the file's path with `.md` removed, full stop.
This gem additionally honors a frontmatter `id:` as an override — an okf
extension, not spec, so a bundle leaning on it is trading portability for the
alias. If you pin one, know the recorded split: links still resolve by path,
so edges land correctly; the identity views (catalog, hubs, search, `--dir`)
follow the id, because the edges do; the physical views (`index`, `dirs`,
stats' `by_dir`) keep the file where it lives, because an index is a physical
listing. A pinned id that disagrees with the path therefore makes the two
families answer differently about where the concept is — prefer the default,
and rename the file when a concept needs a new name.

### `resource` is the bridge to reality <!-- rule:okf-resource-bridge -->
Set `resource` (a canonical URI) **only** when a concept *is* a real, addressable
asset — a table (`bigquery://…`), a service repo, a dashboard, an endpoint. Its
presence is what lets `maintain` find every concept affected by a changed asset in
one `okf search <dir> <uri>` call. Abstract concepts — a decision, a principle, a
metric definition — have no resource, and **omitting it is meaningful**, not
laziness. Do not invent placeholder URIs.

### Links are untyped on purpose <!-- rule:okf-untyped-links -->
A markdown link asserts only "these two relate." The *kind* of relationship —
depends-on, supersedes, derived-from, owns — lives in the **prose around the
link**, never in a made-up typed-edge syntax. Write the sentence that explains the
relationship and put the link inside it. Prefer absolute bundle-relative targets
(`/services/auth-api.md`) so links survive file moves. A link to a concept that
does not exist yet is fine — it is not-yet-written knowledge (§6.1), and `lint`'s
backlog will surface it as demand. One more edge you get for free: a
`sources[].resource` naming another concept **is** a graph edge (§5.1's lineage),
so recording provenance is also linking.

### Provenance lives in `sources`, attribution in footnotes (§5.1) <!-- check:uncited_external -->
Any external or empirical claim — a latency number, an approval, a quota, a
"because X team decided Y" — should be traceable to a `sources:` entry. Each
entry carries at least a `resource` (a URL, a bundle-relative path, or a scope
descriptor like `all queries in project X`), and optionally an `id`, `title`,
and the credibility signals `author` (an actor), `usage_count` (a liveness
signal, never a score), and `last_modified` (`YYYY-MM-DD`). To attribute a
*specific claim*, give the source an `id` and cite it with a markdown footnote
whose label is that id: `sharded daily.[^ga4-schema]` — keyed, not positional,
so a reordered list cannot misattribute silently. `lint`'s provenance category
checks the join in both directions (`unattributed_claim`, `unused_source`).
Uncited claims are exactly how a bundle decays into folklore nobody trusts.
("Citations" is the legacy v0.1 spelling: provenance lived in a body
`# Citations` list, which v0.2 retires — §13.1 keeps it readable, and `lint`'s
Migration findings tell you what to move where.)

### Say who did it, in §7's spelling <!-- check:unprefixed_actor -->
Every `by` — `generated.by`, `verified[].by` — takes an actor in one of §7's
three forms: `<producer>/<version>` (an automated producer, e.g.
`reference_agent/gemini-2.5-pro`), `human:<id>`, or `process:<id>`. The one
producer MUST: content a person hand-authored **or confirmed** is marked
`human:<id>` — §5.3 derives the trust tier from exactly this prefix, so a human
sign-off written `by: owner` silently reads as *machine-confirmed*, the exact
downgrade the tier system exists to prevent (`lint`'s `unprefixed_actor` nudges
it). `sources[].author` is looser on purpose: §7 does not govern it, and the
SPEC's own examples use `team:<id>` there — any honest attribution works.

### Trust is derived, never stored (§5.2/§5.3) <!-- rule:okf-trust-derived -->
`generated` records how the current content was produced (`by` REQUIRED within;
`at` an ISO 8601 datetime); `verified` lists who confirmed it against its
sources — they stay separate because who *wrote* a concept need not be who
*checked* it. Consumers derive the tier: no `verified` ⇒ unverified; machine
actors only ⇒ machine-confirmed; any `human:` verifier ⇒ human-reviewed. Never
write a tier or a credibility score into frontmatter — it would be subjective,
unportable, and stale the moment the next verification lands. And never invent
provenance: a concept whose history you do not know is honestly unverified.
Prefer **block style** for these mappings (`generated:` with indented
`by:`/`at:`): the flow spelling (`{ by: human:x, at: …T10:00:00Z }`) is legal
YAML, but the colons inside its values trip older libyaml parsers, and block
style is the spelling every parser accepts.

### Lifecycle: `status` and `stale_after` (§5.4/§5.5) <!-- rule:okf-lifecycle -->
`status` is one of `draft | stable | deprecated`; absent means `stable`, so
declare it only when it says something. `stale_after` is an absolute
`YYYY-MM-DD` — the author's own "do not trust me past this date", stale **on**
the day itself. Use it for knowledge with a known shelf life (a quota, a
migration window); `lint`'s `expired` check reports the ones whose date has
passed. It is a declared expiry, distinct from the `--stale-after` *flag*,
which is a reader-supplied age cutoff — see [cli/checks.md](cli/checks.md),
rule `okf-two-clocks`.

### Capture the non-obvious — not what code already says <!-- rule:okf-non-obvious -->
A bundle that restates function signatures or config keys goes stale the moment
the code changes and adds no knowledge. Capture what you **cannot** derive by
reading one source file: the *why* behind a design, cross-cutting relationships,
decisions and their tradeoffs, operational tribal knowledge, the metric that
actually matters. If the code or git history already records it faithfully, link
to it rather than duplicating it.

### Write for both readers at once <!-- rule:okf-dual-audience -->
Use structural markdown so an agent can extract deterministically and a human can
skim: headings, tables, fenced code, lists. Conventional headings a reader
expects are `# Schema` (field/column tables), `# Examples`, and — on an Attested
Computation only — `# Computation` (§10.3). Fill recommended frontmatter —
`title`, `description`, `tags`, `generated` — whenever it aids consumption.

### Attested computations are contracts (§10) <!-- rule:okf-computation-untouched -->
A concept of type `Attested Computation` carries a sanctioned computation:
`runtime` is REQUIRED (it fixes what `parameters` mean), the computation is
provided **exactly one way** — a body `# Computation` fence *or* a
`computation:` path, never both — and `executor`/`attester` name how it runs
and how a run is checked. The one new MUST NOT in v0.2 binds the *consumer*: an
agent MAY bind values for the declared `parameters` and MUST NOT author or edit
the computation itself. A "fixed" query silently stops being the one a person
sanctioned; if it is wrong, tell a human. The
[attested-computation template](../templates/attested-computation.md) carries
the whole contract.

### Reserved files <!-- rule:okf-reserved-files -->
`index.md` is a directory listing and carries **no frontmatter** — with one
exception: the **bundle-root** `index.md` is the only index that may carry
frontmatter, and it may carry *only* `okf_version: "0.2"` (§8 states the
exception inline; `validate` flags any other key there under §11 condition 3).
`log.md` is an ISO-dated change history, newest first. Never use these names for
concepts. Templates: [concept](../templates/concept.md),
[attested computation](../templates/attested-computation.md),
nested [index](../templates/index.md), bundle-root
[root-index](../templates/root-index.md), [log](../templates/log.md).

### The log records what shipped, not how it shipped <!-- rule:okf-log-durable-only -->
`log.md` carries durable knowledge and shipped behavior — never the process that
produced them. A bug fixed in a release is an entry; the review rounds that found
it are not. A capability that shipped is an entry; the iterations it took to
stabilize it before it shipped are not. When a change taught a lesson, the lesson
belongs in the concept it is about, stated as a principle, and the log entry
*points* at that concept instead of re-narrating the rounds — a reader finds it
where the subject lives, not by reading history.

The bar is what a reader six months out needs: *what changed and why it matters*,
never *how many passes it took to get there*. Watch for the shape this invites —
the newest entries sit at the top where every reader lands, so a stretch of work
stabilized by iteration accretes "round N found M defects" exactly where a durable
summary belongs.

## Migrating from v0.1 (§13)

A v0.1 bundle is consumable forever — §13.1 sanctions reading `timestamp` as
`generated.at` and a `# Citations` list as `sources` — so migration is
convenience, not rescue. Exactly two spellings retire: `timestamp` (move the
value under `generated: { by: <actor>, at: … }` — the actor is the one thing no
tool can derive; ask, or write `human:<maintainer>` when the history is human)
and the body `# Citations` section (lift each item into `sources`, add `id`s
and `[^id]` footnotes where the body cites, delete the section). `lint`'s two
Migration findings name the files; the [migrate playbook](../playbooks/migrate.md)
walks the rewrite, and `okf lint <dir> --only legacy_timestamp,legacy_citations
--fail-on info` is the mechanical done-check.

## Playbooks

The step-by-step playbooks live in [../playbooks/](../playbooks/), one file per
verb (search, produce, migrate, maintain, consume, curate, doctor), routed by the
Commands table in [SKILL.md](../SKILL.md). The Closeout below is their shared
finishing gate.

## Closeout — the finishing gate <!-- rule:okf-closeout-gate -->

`produce` step 6 and `maintain` steps 4–7 both land here: before calling an
authoring task done, walk this once. It is the repo's "turn every task into a check
that can fail" discipline, and followed literally it catches the enumeration drift
grep can't:

- **Index enumerations** — every `index.md` that lists what you added, renamed, or
  removed is updated; re-run `okf index` and eyeball each listing against reality.
  Easy to skip, expensive to miss — this is the check that was missing.
- **`log.md`** — a dated entry, newest first, and durable only (rule
  `okf-log-durable-only` above).
- **`generated.at`** bumped on the concepts you touched (and `generated.by` says
  who touched them — you, in §7's spelling).
- **`validate`** — zero §11 errors.
- **`lint`** — cheap findings cleared; `expired` reports out of the box, and
  `--stale-after` adds the reader-side age cutoff when you want one.
- **`loose` review + tag curation** — the two semantic passes (maintain steps 6–7);
  worth a pass in `produce` too on a non-trivial bundle.
