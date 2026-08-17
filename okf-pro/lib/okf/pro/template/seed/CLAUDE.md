# What this repo is

`.okf/` is a personal knowledge bundle, not a codebase. Nothing in it
compiles, ships, or has users. The only target is that knowledge stays
**accurate and retrievable** — that a claim can be found by someone who has
forgotten it exists, and that when it is found it is not sitting next to its
own contradiction. A reorganisation that improves nothing findable is waste;
speed of writing is worth almost nothing, cost of retrieval is worth almost
everything.

Everything else at the repository root — this file, `README.md`, `.claude/`,
`.githooks/`, `.github/` — is instruction or plumbing. None of it is a concept,
none of it carries frontmatter, and `okf` never sees it.

# The rules live in the skill

All bundle work — filing a concept, editing the board, journaling, the
snapshot, closing work, anything that touches `.okf/` — follows the
**okf-pro** skill:
[.claude/skills/okf-pro/SKILL.md](.claude/skills/okf-pro/SKILL.md). Use it
before reading from or writing into the bundle. The hooks enforce the
countable half of those rules mechanically; the skill is the whole of them.

It assumes the **okf** skill is also installed, and does not repeat it. That one
teaches the format — what a concept is, what frontmatter it carries, how links
resolve, which verb answers which question — and this one teaches the rules on
top. If it is missing, install it with `okf skill ~/.claude` before filing
anything: the alternative is guessing at a file shape the gates will then refuse.

Scratch work goes under `.tmp/` at the repository root — outside the bundle
entirely.

# The three doors

The same invariants are asked three times, because each door sees edits the
others never do:

* **agent-time** — `.claude/hooks/` fire at the tool boundary, before and
  after every write into the bundle;
* **commit-time** — `.githooks/pre-commit` audits the *staged* tree. It needs
  one setup per clone, because git hooks do not travel with a checkout:

  ```sh
  git config core.hooksPath .githooks
  ```

* **push-time** — `.github/workflows/okf-pro.yml`, for the edit made on a
  machine that never configured the hook, or committed with `--no-verify`.

All three fail **closed**: a gate that cannot run refuses rather than passing.
A gate that waved things through because its checker was missing would have
converted "unchecked" into "checked and fine", which is worse than having no
gate at all.

# This file is yours

`okf pro upgrade` rewrites the four governance files it owns — the hook
wrapper, the pre-commit hook, the workflow, the skill — and never touches this
one, `README.md`, `.gitignore`, `.claude/settings.json`, or anything under
`.okf/`. Those were seeded once and are yours from that moment. Add to this file whatever
else an agent working in this repository needs to know.
