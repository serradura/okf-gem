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
   document's own heading and purpose line, `timestamp` from the document's own
   date when it carries one, `tags` only where connective.
3. **Keep the directory topology** — it is already domain knowledge. Default
   one file = one concept. When a file shows split signals (two `type`s
   fighting for the frontmatter, two audiences), flag it for a later `curate`
   pass; never split, rename, or restructure during migration.
4. **Reserved files.** A bundle-root `index.md` from
   [templates/root-index.md](../templates/root-index.md) (frontmatter is
   `okf_version: "0.1"` and nothing else), a nested `index.md` per directory
   from [templates/index.md](../templates/index.md), and `log.md` with a dated
   **Creation** entry naming where the documents came from.
5. **Links.** The documents' existing relative links become the graph's edges —
   verify they resolve inside the bundle and repoint only what a move broke.
   Links pointing outside the bundle are tolerated (§5.3); leave them.
6. **Close out** — walk the
   [Closeout gate](../reference/authoring.md#closeout--the-finishing-gate):
   `validate` zero errors, `lint` (pass `--stale-after` when you stamped
   timestamps), `loose`, tag review, index eyeball. Then prove the promise:
   each concept with its frontmatter block stripped is byte-identical to the
   source document.
