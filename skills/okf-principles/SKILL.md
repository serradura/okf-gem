---
name: okf-principles
description: Restructure agent instruction artifacts (Claude Agent Skills, rules files, CLAUDE.md, playbooks) by applying five structural principles derived from the Open Knowledge Format - bounding the worst-case context a question loads (the mean may rise; the win is the tail and answer accuracy) and making cross-references survive rewrites. Use this skill whenever the user wants to split a monolithic skill or reference file, reduce context loaded per question, add an index layer, make cross-references survive rewrites, or audit a skill's structure for efficiency. Also use it when the user mentions progressive disclosure, token-efficient skills, or restructuring instructions for agents.
---

# okf-principles

Restructures instruction artifacts so an agent loads only what a question
needs. The measured payoff is the tail, not the average: a split bounds
the worst-case context per question and removes the cheap confident
wrong answers blind scrolling produces - mean bytes may rise slightly,
and that is not a failure. This file is the index: read the one
principle file the task calls for, not all five.

## The five principles

* [Index first](references/index-first.md) - the reader decides what to
  load, so structure must be inspectable before it is consumed. Read when
  splitting a monolith, writing an index, or indexing a vendored or
  generated file you cannot edit.
* [Keyed identity](references/keyed-identity.md) - references are keyed,
  never positional, because agents rewrite. Read when adding rule IDs or
  fixing cross-references before a file move.
* [Permissive reading](references/permissive-reading.md) - partial
  structure must still work. Read when writing reader-side instructions
  or migrating incrementally.
* [No tooling required](references/no-tooling.md) - plain text that
  survives being read as prose. Read when tempted to add a format,
  schema, or parser.
* [Kind over location](references/kind-over-location.md) - a file
  declares what it is; folders are free to change. Read when organizing
  directories or labeling index entries.

## Procedure for restructuring an existing skill

1. Inventory: list every file, its line count, and what questions it
   answers. A file answering unrelated questions is a split candidate.
   Mark any file that is vendored, generated, or third-party: those are
   never split - they get an index beside them instead (see
   rule ss-index-beside-foreign).
2. Split along question boundaries, not size. Each resulting file should
   answer one family of questions (per verb, per workflow, per format).
3. Write the index per [index-first](references/index-first.md). Every
   entry needs a description an agent can route on, and coverage must
   match the index's claim - especially for an index promoted from
   inside a file, which inherits its old host's narrower scope silently
   (rule ss-coverage-matches-claim).
4. Key every rule worth citing per
   [keyed-identity](references/keyed-identity.md), then repoint existing
   cross-references at keys instead of paths and section names.
5. Add reader guidance per
   [permissive-reading](references/permissive-reading.md) so a half
   migrated state stays usable.
6. Verify against the anti-goal with a fixed question set, judging the
   worst question rather than the mean (rule ss-measure-worst-case): one
   that loads more files or bytes than before names the boundary to
   merge back. Where a topic moved between files, leave a pointer at the
   old seam (rule ss-seam-pointers).

## Anti-goals

Do not port machine-oriented metadata (trust tiers, provenance chains,
attestation, changelogs) into a skill. Those solve multi-agent corpus
problems; a skill has one author and lives in version control. Do not
add frontmatter keys beyond what the host harness defines unless a
machine must read them; prefer expressing structure in the index body,
which no harness parses. <!-- rule: ss-no-ceremony -->
