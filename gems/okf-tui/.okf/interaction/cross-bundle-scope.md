---
type: Concept
title: Active Bundle and Scope Are Two Axes
description: What you are reading and what you are searching move independently, and the registry writes that reconcile them key on the directory rather than the slug.
tags: [ux, search, registry]
generated:
  by: human:maintainer
  at: 2026-07-19
sources:
  - title: "`lib/okf/tui/workspace.rb` — `reload`, `add`, `remove`, `make_default`, `rename`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/workspace.rb
  - title: "`test/test_helper.rb` — `with_registry`; `test/integration/terminal_test.rb` — the unchanged-registry assertion."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/test_helper.rb
---

# Overview

"Which bundle" is two questions, and collapsing them into one would be the
obvious mistake:

- the **active bundle** (`●`) — what browse, graph and health are about. `Enter`
  on a bundle changes it.
- the **scope** (`◉`) — which bundles a search covers. `space` toggles one, `A`
  all, `N` none.

So you can read one bundle while searching all of them. Opening a hit that lives
in a *different* bundle switches the active bundle to it, which is the one place
the axes meet.

Scope is not a filter applied after the fact: the scoped bundles are indexed
**together**, as one corpus, so BM25 scores compare across them rather than only
within one. That is the same thing `okf search @all --fuzzy` does, and the reason
for [the facade coupling](/decisions/search-facade-coupling.md) — which is also
where the `fuzzy: true` that selects the BM25 engine at all is explained.

# Reconciliation keys on the directory

Every registry write reloads from disk, so the screen shows what the file now
says rather than what the in-memory list was talked into believing. That reload
has to carry the scope forward, and *how* it matches bundles is where three real
bugs lived:

| Bug | Cause | Fix |
|-----|-------|-----|
| a renamed bundle silently dropped out of scope | scope matched on slug, which a rename changes | reconcile on the **directory**, which survives a rename |
| setting a default moved the row under the cursor | the list reorders; the cursor held a position | the cursor follows the *bundle*, not the index |
| a newly added bundle was outside scope | the prior scope cannot mention a slug that did not exist | add it explicitly on add |

The through-line: **a slug is a label, the directory is the identity.** Anything
that has to survive a registry edit keys on the path.

# The registry is the user's config

Registry writes are real writes to the user's file. Removing a bundle never
touches the bundle on disk — the registry is a list of references — and a
workspace of directories named on the command line has no registry at all and
says so rather than pretending to configure one.

The suite never touches the real `~/.okf`: every test runs against a temporary
`$OKF_HOME`, and the pty test asserts the registry file is byte-identical
afterwards.
