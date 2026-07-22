# Playbook: refine — restructure a bundle to get the most from OKF

Reach for this when the bundle's *content* is right but its *shape* may not be:
areas grown fat by additive passes, hubs homed by history, a tag layer that
never became the second index. Refine optimizes the projection — the same
knowledge, arranged to serve progressive disclosure, the emergent graph,
cross-cutting tags, and capture-once-link-many. It is not [curate](curate.md)
(upkeep of the structure as it stands) and not [maintain](maintain.md) (content
catching up with reality): refine changes where knowledge lives, never what it
says. Its permitted edits are structural — move a concept, extract a duplicated
fact to one home, section an index, retag, relink, and write the connective
sentence a link lives in; summarizing, updating, or correcting a body is
maintain's job, reached by switching verbs, not by stretching this one.

The frame that governs every move: the directory tree is a **lossy projection
of the link graph**. A tree gives each concept one parent, so the tree encodes
only the single dominant decomposition; every genuinely many-to-many
relationship rides links and tags, never new directories. And cohesion outranks
balance — a move has semantic cost, so balance is a tiebreaker and a fatness
alarm, never the objective. <!-- rule:okf-cohesion-over-balance -->

1. **Orient.** `okf dirs <dir|@slug>` (directories, fan-out, depth — and
   `subtree` says where the weight sits), `log.md` (how the bundle grew), `okf
   stats` (totals). Additive growth
   optimizes each pass locally, never the whole — that is the drift this
   playbook corrects.
2. **Measure — the CLI is the evidence.** Baseline `validate` / `lint
   --stale-after` / `loose` first: refine assumes a sound bundle, and hard
   errors are [curate](curate.md)'s job. Then the two structural reads:
   - `okf tags <dir> --by dir` — each row carries `count/total`, so a tag's
     **locality** reads directly: a tag wholly inside one area names a *domain*
     (the directories are right); one spread across areas names a *concern*.
   - `okf graph <dir> --hubs` — concepts ranked by inbound links, each with
     the areas those links come from: the **origin test** for every hub.
3. **Diagnose — you are the judgment.** The measurements are evidence, never
   verdicts:
   - **Concerns never become containers.** A directory built around a spread
     tag ("everything async") prunes nothing — most needs would enter it.
     The cross-cut stays a tag. <!-- rule:okf-concern-not-container -->
   - **A directory must prune.** The positive test for any area, existing or
     proposed: does knowing "it's in there" eliminate a large, even slice? A
     good node splits its parent into chunks that are nameable, mutually
     exclusive, and roughly comparable in size. And small is not merge-worthy
     on its own — a two-concept area that is a genuinely distinct domain
     stays. <!-- rule:okf-directory-prunes -->
   - **The hub origin test.** Inbound majority from the hub's own area:
     well-homed, leave it. A dominant *foreign* area: that area is the better
     home. Foreign majority with *no* dominant area: a shared primitive — the
     only admission ticket into a shared-core area (without that test, a
     `foundation/` rots into a `misc/`). Two comparable strong ties, one of
     them home: stay and carry the other as a tag — moving trades one
     imbalance for another. And in a design bundle expect the central
     decisions to fail this test wholesale: that is centrality, not
     mis-homing.
   - **Fatness alarm, not fatness rule.** A fat area (≳20–25 concepts) wants
     **heading sections inside its `index.md`** first — the same prune as
     sub-directories, for zero extra hops and no new enumeration to keep
     sound. Directory nesting pays only at hundreds of concepts, and only
     where the index's own headings already form separable, nameable
     sub-groups — fatness alone never justifies depth; the sections that
     formed are the evidence the split exists.
   - **Duplication.** Read the area overviews for a fact re-explained in
     several (drifting tables are the tell); capture-once-link-many says
     extract it into one concept and link from the rest. Extraction is the one
     refine move that touches bodies, and it redistributes rather than
     rewrites: assemble the canonical concept from the copies, keep every
     copy's unique domain-specific detail (in the extract, or in the one-line
     note left beside each link), and where the copies *disagree*, which is
     true is a [maintain](maintain.md) question — verify against reality or
     flag the conflict in the proposal, never silently pick a winner while
     merging. <!-- rule:okf-extract-not-rewrite -->
   - **Vocabulary twins.** The [maintain](maintain.md) tag-curation recipe
     (twins, echoes, singletons) applies to `type` too — `okf types <dir>`.
4. **Plan — tier by leverage ÷ churn, free levers first.** Tag curation,
   index heading-sectioning, and extraction before any file move; a move only
   when the origin test demands one, and each gated by **do-nothing**: skip it
   unless its value beats its churn. Record what you *declined* and why — the
   decline list is what stops the next pass from re-proposing it.
5. **Propose — never auto-apply.** Refine's output is a short report (the
   evidence, the tiers, the declines) plus a ready-to-run execution prompt the
   user can hand back later: a scope line, the governing principles above, the
   explicit prohibitions, the closeout gate as acceptance. Analysis and
   execution are separate on purpose — the judgment is spent once, frozen, and
   then executed without re-derivation. <!-- rule:okf-refine-proposes -->
6. **Execute only on approval**, then walk the
   [Closeout gate](../reference/authoring.md#closeout--the-finishing-gate):
   every touched `index.md` re-enumerated, links absolute bundle-relative so
   they survived the moves, a dated `log.md` entry carrying the *why*,
   validate/lint/loose clean, and a before/after of step 2's evidence.

Two traps: never split a cohesive cluster (a deliberately paired mirror flow)
to hit a size band, and never tag a concept with its own directory's name — a
group-name echo adds no edge.
