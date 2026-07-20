---
type: Constraint
title: Integration tests are the critical layer
description: The CLI is the product, so the suite that drives it end to end outranks the unit tests — and its coverage is measured alone, because the full number flatters.
resource: test/integration/cli
tags: [testing, cli, architecture]
timestamp: 2026-07-20T12:00:00Z
---

# Overview

A unit test proves a method behaves; an integration test proves the *product*
behaves. For this gem the product is the [CLI](../cli.md) — real argv, real
streams, real exit codes, real files — so when the two compete for effort,
integration wins. That is a ranking, not a slogan: `test/integration/cli/` is
where a new verb is proven, and a verb without its file is not done.

The [core/shell split](core-shell-split.md) is what makes both layers cheap: the
pure core is unit-testable without disk, and the shell is thin enough that
driving it for real costs milliseconds.

# The folders are the three ways a user names a bundle

```
test/integration/cli/
  cli_integration_case.rb   the shared base: okf(), with_registry(), okf_server()
  fixtures/                 bundles more than one group uses
  by_dir/                   `okf lint ./docs`      — named by path
  by_registry/              `okf lint @handbook`   — named through the registry
  across_bundles/           `okf search @a @b`     — several at once
  cli_help_test.rb …        the verbs that name no bundle
  cli_plugin_test.rb        the extension seam — a plugin on the load path
```

`cli_plugin_test.rb` is the odd one, deliberately: it names no bundle and tests
no verb of ours. It writes `okf/plugin.rb` into a temp dir on `$LOAD_PATH`, which
is indistinguishable from an installed gem's `lib/`, so the
[seam](extension-points.md) is driven for real without building and installing a
gem to drive it.

Same command, same flags, three identities — because the identity is where the
CLI decides *what to answer about*, and a verb that works by path can still be
broken by [ref](../registry.md). One file per command **and** per subcommand:
`registry list`/`set`/`del`/`default`/`rename` are five files, since each is a
surface invoked on its own.

`across_bundles/` covers every bundle-taking verb, not only the two that merge.
For the eleven with no multi-bundle form, the test proves a second bundle is
*rejected* — that boundary was a real silent-wrong-answer bug (`okf lint a b`
once linted `a`, ignored `b`, and exited `0`), so it is guarded, not assumed.

# Coverage is measured on the layer alone

```bash
bundle exec rake test:integration   # + coverage/integration/
```

The full suite's number flatters: unit tests call classes directly and reach code
no user can. Run integration by itself and the figure becomes a *map* instead of
a score — read it that way. Low coverage in `bundle/writer.rb` or
`concept/file.rb` is expected and honest: no CLI verb writes a bundle, so those
belong to the [library API](../capabilities/library-api.md) to prove. Low coverage
in `cli/`, `registry.rb`, or `server/` is a **hole** — a path a user can reach
that no user-shaped test walks.

# Fixtures are the cheap part

`fixtures/` is the substrate the whole layer stands on: a committed bundle is
cheaper than a mock, more honest, and a reviewer can read it. When a path is
unreachable from the fixtures that exist, **add one** — never bend a test toward
what the fixtures happen to make easy, and never leave a path untested because
building its world felt like work.

Two of them are the argument. `rooted` exists because `tags --by area`'s `(root)`
label — the one printed without a trailing slash — was unreachable from all twelve
fixtures before it: none carried a *tagged* root-level concept. `mentions` exists
because none contained a literal `@`, so
[search](../capabilities/search.md)'s `-e '\@term'` escape could be shown not to
error but never shown to *find*. A branch no fixture can reach is a branch nobody
has ever proven.

Fixtures follow **common closure**: one that a single group uses lives under that
group, so it changes when those tests change; one that several share stays in the
shared `fixtures/`. The base resolves group-local first, shared second, so a test
says `fixture("navigation")` without knowing which it is.

# Why it pays off

The suite is not decoration — writing it is what found the bugs. The pass that
built this layer turned up a `render -o` backtrace where the exit contract
promised `2`, counts that disagreed with their nouns, three spellings of "no
usable type" in three buckets, a [`graph`](../capabilities/read-views.md) that
named no bundle at all, and the silent second-bundle answer above. Four
independent reviewers had read the same code first and found none of them.

Assertions must be able to fail for a real reason: run the CLI, read what it
actually prints, then assert *that*. Asserting what you assume the code does is
how a green suite certifies a bug.

# The order is the proof

A change starts with a failing integration test, not with the fix — and the
failure has to be *read*, not merely observed: it must fail for the predicted
reason, since a test that fails on a missing fixture or a typo'd regex has proven
nothing about the bug. Then the code, then a re-run the test passes unedited.
<!-- rule:okf-test-first -->

That order is the only thing that establishes a test *can* fail. Written
afterwards, a test can only certify the code it was read off; written alongside,
a bug and its test come to agree with each other and stay wrong together — the
green suite certifying a bug, arrived at from the other direction. Pure refactors
are the exception rather than a licence, because they change no behavior: the
existing suite is their test and a green run is the proof the contract held.

The registry's [two derivations of the default](../registry.md) are the worked
example. The star-versus-`/` disagreement was written as a red test first, and the
run printed both halves of the bug at once — `/` redirecting to `conformant` while
the listing starred a `doomed (missing)` entry. Neither the reviewer nor the fix
had to be trusted: the test failed for exactly the predicted reason, the fix
turned it green, and it has guarded the agreement since.

# Citations

[1] [AGENTS.md — Testing: integration first](https://github.com/serradura/okf-gem/blob/main/AGENTS.md) — the rule as the maintainer guide states it.
[2] [test/integration/cli/cli_integration_case.rb](https://github.com/serradura/okf-gem/blob/main/test/integration/cli/cli_integration_case.rb) — the shared base: the scratch registry, the non-booting server runner, group-local fixture resolution.
