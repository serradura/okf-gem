---
type: Decision
title: Setup writes what it can, and refuses exactly one thing
description: A collision is staged beside the adopter's file rather than refused; a root-level bundle is refused outright, because writing there manufactures an ambiguous layout.
---

# Never refuse wholesale

A repository that already has a `CLAUDE.md` is the common case, not an error.
`setup` writes everything it can and stages the rest as `<path>.okf-pro-new`,
with a printed merge instruction. A stale staged file is **refreshed**, never
doubled — there is no `.okf-pro-new.okf-pro-new`.

Which files can collide at all is a question of [who owns them](/scaffold/ownership-not-subject.md):
inside `.okf/` nothing is ever staged, only completed.

# And the one refusal has to ask the question it cites

The refusal names `Audit.ambiguous_layout` as the state it prevents, and for a
while it did not ask what that finding asks. The finding tests `root_kind` —
`index.md` **plus** `board.md` or `log.md`, or an `okf_version` in the
frontmatter. The refusal tested `bundle?`, which is `index.md` alone.

So every Jekyll section, every Hugo directory, every repository with an
`index.md` README was refused at its first `okf pro setup`, and told to
`git mv index.md log.md <your dirs> .okf/` — files that have nothing to do with
OKF, for an ambiguity the audit would never have reported. A first run is the
one moment an adopter has no reason to trust the tool yet, and this spent that.

**A refusal that cites a finding has to be answering the question that finding
asks.** Two predicates for one condition is one predicate too many, and the
looser one always wins the argument by refusing more.

The generated `.gitignore` lists `*.okf-pro-new`, and that line is
load-bearing: inside `.okf/` those files are invisible to `validate` and `lint`
because they are not `.md`, so without it they get committed and nothing ever
says so.

Which is why the merge instruction **reads the adopter's tree rather than
assuming it**. The closing line used to state flatly that `.gitignore` already
ignores them, and that was false in the one case where it mattered: when
`.gitignore` is itself the collision, the adopter's own file stays on disk and
the template's — the copy carrying the line — is what got staged beside it. A
report that says "already ignored" about files git is about to commit is the
same silence one paragraph up, produced by the fix for it.

# The one refusal

A bundle whose root **is** the repository root. Writing `.okf/index.md` beside
it collides with nothing, so a naive generator succeeds — and leaves two bundle
roots in one directory, which is exactly the state `Audit.ambiguous_layout`
exists to report, where the three doors disagree until one of the two is
retired.

`setup` detects it and exits 2 naming the migration, which is one `git mv` the
adopter can see. Manufacturing a state your own audit is written to complain
about is worse than refusing to start.

# Atomicity, stated honestly

Each file is written to a temp path in its destination directory and renamed, so
**no half-written file exists**. A nineteen-file sequence is not atomic as a
*set*, and this does not pretend otherwise. The real safety is that `setup` is
idempotent and re-runnable, which is what makes an interrupted run harmless.

# Two mechanics worth keeping

The `.gitignore` template is stored as `gitignore`, without the dot. As a real
dotfile in the gem's own tree it would be a live gitignore governing its own
directory — silently deciding what `git ls-files` reports, and therefore what
ships.

The generated file list is compared against `spec.files`, **not** against a glob
of the template. Both sides of a glob-versus-glob comparison ignore
`.gitignore`, so such a check passes in a checkout while the installed gem is
short files — which is the failure it exists to catch.
