# Checking a bundle — `validate`, `lint`, `loose`, `references`

Kind: reference. Answers: what makes a bundle non-conformant, what each lint
check means and the severity it is pinned at, which of the two clocks a flag
reads, and which dangling pointers each surface can and cannot see.

The shared contract — `@slug` refs, exit codes, `--json`, the filters — is in
[cli.md](../cli.md) and is not repeated here.

## validate — the hard gate (§11)

Implements the spec's §11 conformance definition exactly (its words are in
[SPEC.md](../SPEC.md), routed by [spec-map.md](../spec-map.md)):

- **§11 cond. 1** every non-reserved file has a parseable YAML frontmatter block;
- **§11 cond. 2** every such block has a non-empty `type`;
- **§11 cond. 3** any `index.md`/`log.md` present follows §8/§9 (a nested
  `index.md` has no frontmatter, a root `index.md` carries only `okf_version`,
  `log.md` date headings are ISO `YYYY-MM-DD`).

`ERROR`s are the three conditions above; the bundle is non-conformant until every
one is fixed. `warn`s are soft — missing recommended fields, non-list tags, an
unparseable timestamp, **broken cross-links, which §6.1 explicitly tolerates**,
the shape of every §5/§10 family (`generated` not a mapping, a non-integer
`usage_count`, a `stale_after` that is not `YYYY-MM-DD`, a missing `runtime` on
an Attested Computation, …), and an `okf_version` the gem does not know (read
best-effort under §12; an absent one never warns). Absence of an optional family
is never a fault — a pure v0.1 bundle validates with zero warnings.

In `--json`, every warning carries `check` (a stable id) and `source` — `spec`
when the SPEC's own words state the rule, `convention` for a shape this gem asks
for beyond them (`verified[].by` presence, integer `usage_count`, a per-entry
`usage_window` mapping, `parameters[].name`, `executor`/`attester` `resource`).
Gate on `source` when you want only the spec-normative set; errors keep their
two-key `{ path, message }` shape. Fix warnings when cheap; never block on them.
Use `--json` in CI.

## lint — curation quality (advisory)

Asks the complementary question to `validate`: not "is this legal OKF?" but "is
this well-curated, navigable, trustworthy?" — precisely over the things §11
forbids `validate` from rejecting. It has its own report, never emits
conformance errors, and **exits `0` even with findings** unless you pass
`--fail-on warn` (exit 1 on any `warn` finding) or `--fail-on info` (exit 1 on
any finding at all).

**Severity is API.** Every check has a pinned level — `warn` or `info` — and
machine consumers gate on it, so the levels below are stable, not advisory. A
finding you want to gate on that is `info` gets `--fail-on info` (usually with
`--only`), never a hope that its severity changes. <!-- rule:okf-severity-is-api -->

Eight categories, each backed by individual checks (severity in brackets):

- **Reachability** — `orphan` [warn], `not_in_index` [warn],
  `disconnected_component` [info], `unlinked` [info]
- **Backlog** — `missing_concept` [info], `broken_index_entry` [warn]
- **Completeness** — `stub` [info], `missing_title` [info],
  `missing_description` [info], `missing_generated` [info] (quiet on either
  spelling — a legacy `timestamp` still counts as a recorded change)
- **Freshness** — `expired` [info] (§5.5: past the concept's own declared
  `stale_after`, on the day itself), `stale` [warn] (older than the
  reader-supplied `--stale-after` cutoff, keyed on `generated_at`)
- **Provenance** — `uncited_external` [info] (external body links and no
  sources, in either spelling), `broken_source` [warn] (an in-bundle `.md`
  source target that names no concept; URLs and scope descriptors are out of
  scope, and a non-`.md` asset is out of reach — the reader models concepts,
  so lint never sees the file; `okf references` is the view that checks those
  pointers), `unattributed_claim` [warn] (a footnote
  no `sources[].id` answers — it *misattributes* a claim, which is why it
  outranks its join-twin), `unused_source` [info] (a keyed source no footnote
  cites — slack, not a defect), `unprefixed_actor` [info] (a `verified[].by`
  outside §7's three forms reads as machine-confirmed; a `generated.by`
  outside them feeds no tier but leaves a reader unable to tell a person
  from a process; info so it informs, never blocks). A missing `generated.by` is the *validator's* warning —
  REQUIRED-within is shape, not curation — so lint never double-reports it
- **Attestation** — `incomplete_computation` [warn] (an Attested Computation
  providing its computation neither way, or both ways — §10.3 says a
  `computation:` path is used *instead of* the body fence),
  `broken_attestation_ref` [warn] (on an `Attested Computation`, a
  `computation`, `executor.resource` or `attester.resource` naming an
  in-bundle `.md` that is not there — a contract no consumer can follow; the
  keys are read only on that type, since §4.1 lets any other concept use them
  for its own purpose). Its reach is exactly the `.md` files: URLs are out
  of scope, and a `.sql` or `.py` target is invisible to *every* check here,
  because the linter reads the concept model and the model carries only
  markdown — `okf references` is the surface that sees those files and reports
  a pointer that misses, whatever the extension. Remember §6.2 reads a bare
  `references/…` as relative to the concept, so from a nested concept it wants
  the leading `/`
- **Migration** — `legacy_timestamp` [info], `legacy_citations` [info]: one
  finding per bundle naming the files still in a retired v0.1 spelling, with
  the rewrite instructions in the message. Info on purpose — §13 says a v0.1
  bundle is consumable forever, so `--fail-on warn` must not turn red on one.
  A migration campaign gates explicitly:
  `okf lint <dir> --only legacy_timestamp,legacy_citations --fail-on info`,
  exit 1 until clean.
- **Hygiene** — `duplicate_title` [info], `unused_reference_def` [info],
  `undefined_reference` [warn], `self_link` [info], `log_order` [info] (§9
  reads a log newest-first; disorder is slack, never a §11 error)

`--only` / `--except` filter by the **individual check names above**, not the
category labels — `okf lint <dir> --only orphan,stub` works; `--only reachability`
is an error. Two knobs tune specific checks: `--min-body N` sets the `stub` body
threshold in characters (default 50), and `--stale-after DUR` sets the `stale`
cutoff — a duration like `90d` or `12w`, or an ISO date like `2026-01-01` (a bare
number is rejected).

**Two different clocks, one unlucky name.** The `--stale-after` *flag* and the
`stale_after:` *frontmatter field* are different mechanisms that happen to share
a spelling. The flag is the **reader's** age cutoff: "flag anything not touched
since DUR", keyed on `generated_at`, feeding the `stale` check. The field is the
**author's** declared expiry: "do not trust this past DATE", feeding the
`expired` check. Never read one as the other, and never show them adjacent
without the distinction. <!-- rule:okf-two-clocks -->

**The clock is explicit.** `expired` compares against a day the CLI supplies —
today by default, or `--today YYYY-MM-DD` for a reproducible report (CI wants
this). The pure library runs no clock check unless handed `today:`, and every
clock-gated check that was selected but could not run is *named* in
`stats.skipped_checks` (the human report prints one `skipped:` line) — a gate
that is sometimes absent and does not confess converts "unchecked" into
"checked and fine".

The report's stats carry the bundle's posture too: `trust` (the §5.3 tier
distribution, in the hyphenated wire spelling) and `status` (effective-status
frequency).

`lint --json` is the structured substrate you consume to reason about the two
things lint deliberately does **not** compute — contradictions and *semantic*
staleness — which need understanding of meaning.

## loose — files with no graph connections (by folder)

Lists the **loose** files — concepts with graph **degree 0**: no cross-links in
*or* out — grouped by folder. It is a focused, folder-organized view over `lint`'s
`unlinked` check (`okf loose <dir>` ≈ `okf lint <dir> --only unlinked`, regrouped),
for the "which files float in the graph?" question. Advisory: **exits `0`**; `--json`
emits `{ bundle, count, loose: [{ id, title, dir }] }`.

**Loose ≠ orphan** — the trap. `lint`'s `orphan` is about *reachability*, and an
`index.md` listing makes a file reachable, so an indexed file is never an orphan.
But an index listing is **not a graph edge**: a file can be listed in an index yet
have no cross-links, so it floats in the graph while `lint` reports it as reachable.
`loose`/`unlinked` catch exactly that gap. A loose file is not automatically a
defect — a terminal leaf (a backlog item, a spec reference) can be loose by design;
`loose` surfaces the set so you can judge intent (see the
[maintain playbook](../../playbooks/maintain.md)).
<!-- rule:okf-loose-not-orphan -->

## references — the `references/` inventory (§6.3)

Lists every file under `references/` — including the non-markdown ones no other
verb can see, since the concept model carries only markdown — with which
concepts cite each file through the §6.2 path-valued fields (`resource`,
`sources[].resource`, `computation`, `executor.resource`, `attester.resource`),
plus every pointer into `references/` that resolves to nothing. Advisory:
**exits `0`** even with dangling pointers — the findings are the output. JSON:
`{ bundle, dangling, count, references: [{ path, dir, kind, referenced_by }] }`,
with `--fields`/`--except` projecting the rows. A file that is itself a concept
(§6.3 allows both) is marked `kind: "concept"`; body links are the graph's
business and are not counted here.

**The dangling list is where §6.2's bare-path trap surfaces.** A bare
`references/attesters/rev.py` written from `metrics/` resolves relative to the
concept — `metrics/references/attesters/rev.py`, nothing — and when the
leading-slash spelling would have hit, the entry says so:
`/references/attesters/rev.py exists — missing leading slash?`. Reach is any
extension, which is exactly what `broken_source` and `broken_attestation_ref`
cannot offer (their exemptions above), so run it wherever a bundle carries
attester code or computation files.

