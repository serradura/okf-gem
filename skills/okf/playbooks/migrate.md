# Playbook: migrate — OKFy existing docs in place

Adopt documentation that already *is* the knowledge: frontmatter on, reserved
files in, every body kept **verbatim**. The output must be recognizably the
input — when the documents should instead be distilled into new concepts, that
is [produce.md](produce.md), not migrate. If the `okf` CLI is missing, stop and
follow [doctor.md](doctor.md) first.

Bodies are sacred: migrate never rewrites, reorders, or summarizes a body — the
one permitted edit besides prepending frontmatter is repointing a relative link
that a file move broke. <!-- rule:okf-migrate-verbatim -->
Read the modelling craft in [authoring.md](../reference/authoring.md) before a
non-trivial migration; its type and tag rules apply here unchanged.

1. **Inventory from the validator, not by eyeballing.** `okf validate <dir>
   --json` enumerates every file missing frontmatter or `type` and every
   malformed reserved file — that list is the worklist, and the pass is done
   when it reports zero.
2. **Prepend frontmatter; do not touch the body below it.** Use the frontmatter
   block of [templates/concept.md](../templates/concept.md): a small `type`
   vocabulary derived from what the documents *are* (reuse before minting —
   check `okf types <dir>` as you go), `title`/`description` from each
   document's own heading and purpose line, `generated: { by: <actor>, at: … }`
   from the document's own history when it carries one (the actor in §7's
   spelling — never invented), `tags` only where connective.
3. **Keep the directory topology** — it is already domain knowledge. Default
   one file = one concept. When a file shows split signals (two `type`s
   fighting for the frontmatter, two audiences), flag it for a later `curate`
   pass; never split, rename, or restructure during migration.
4. **Reserved files.** A bundle-root `index.md` from
   [templates/root-index.md](../templates/root-index.md) (frontmatter is
   `okf_version: "0.2"` and nothing else), a nested `index.md` per directory
   from [templates/index.md](../templates/index.md), and `log.md` with a dated
   **Creation** entry naming where the documents came from.
5. **Links.** The documents' existing relative links become the graph's edges —
   verify they resolve inside the bundle and repoint only what a move broke.
   Links pointing outside the bundle are tolerated (§6.1); leave them.
6. **Close out** — walk the
   [Closeout gate](../reference/authoring.md#closeout--the-finishing-gate):
   `validate` zero errors, `lint`, `loose`, tag review, index eyeball. Then
   prove the promise: each concept with its frontmatter block stripped is
   byte-identical to the source document.

## The other migration: v0.1 spelling → v0.2

A bundle already in OKF but written in v0.1's spelling reads correctly forever
(§13.1), so this pass is convenience — run it when you want the bundle to *write*
what v0.2 readers expect. Exactly two spellings move, and `lint`'s Migration
findings name every file carrying either:

1. Run `okf lint <dir>` and read the two Migration findings — `legacy_timestamp`
   and `legacy_citations` list the affected files in their metric.
2. **`timestamp` → `generated`.** Move the value under
   `generated: { by: <actor>, at: <the timestamp> }`. The actor is the one thing
   no tool can derive: ask, or write `human:<maintainer>` when the history is
   human — and never let a tool sign a person's name (see
   [produce](produce.md)).
3. **`# Citations` → `sources`.** Lift each item into a `sources:` entry —
   a labelled link's text becomes `title`, its URL `resource`; a bare-URL or
   autolink item has no title, so keep `resource` alone or author one. Where
   the body cites a source, add an `id:` to the entry and a `[^id]` footnote at
   the claim. Then delete the section.
4. Re-run `okf lint` until the Migration category is clean. The mechanical
   done-check, exit 1 until it is:
   `okf lint <dir> --only legacy_timestamp,legacy_citations --fail-on info`.
