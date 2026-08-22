---
type: Constraint
title: Which Registry a Session Is On
description: okf resolves a project-local .okf-registry.json before the global $OKF_HOME one; the TUI did not, and being the single verb that disagreed was a silent wrong answer rather than an error.
tags: [registry, okf-coupling, discovery]
generated:
  by: human:maintainer
  at: 2026-08-13
sources:
  - title: "`lib/okf/tui/workspace.rb` — `open_registry`, and `registry_path` asking the registry rather than recomputing from `home`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/workspace.rb
  - title: "okf `lib/okf/registry.rb` — `Registry.load(home:, cwd:)`, `LOCAL_FILE`, `NO_DISCOVERY_ENV`, and `#reopen` with the comment recording what a bare `new` costs."
    resource: https://github.com/serradura/okf/blob/main/gems/okf/lib/okf/registry.rb
  - title: "okf `CHANGELOG.md` 1.12.0 — `okf registry init`, relative path storage, and the hub bug that `#reopen` fixed."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/CHANGELOG.md
  - title: "`test/integration/refs_test.rb` — the local/global pair, `OKF_NO_DISCOVERY`, and the embedding-app case that must stay global-only."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/integration/refs_test.rb
  - title: "Reproduced 2026-08-13 in a scratch project: `Registry.load(cwd: pwd).path` → `<project>/.okf-registry.json`, `Registry.load.path` → `<home>/registry.json`."
    resource: "Reproduced 2026-08-13 in a scratch project: `Registry.load(cwd: pwd).path` → `<project>/.okf-registry.json`, `Registry.load.path` → `<home>/registry.json`"
---

# Overview

"Which bundles can I see?" has one right answer per directory, and okf decides it:
`OKF_NO_DISCOVERY` forces the global registry; otherwise a `.okf-registry.json`
found by walking up from the working directory wins; otherwise `$OKF_HOME`
(default `~/.okf`). Nearest local file wins, and a local registry stores paths
*relative* to itself so it can be committed and travel with the repo.

The TUI ignored all of that for a release. `Workspace` called
`OKF::Registry.load(home: home)` with no `cwd:`, and okf only discovers when it is
handed one — so inside a repo carrying a local registry, `okf registry list` and
`okf server` read the local file while `okf tui`, one keystroke away, read the
global one.

# Why it was worse than an error

Nothing failed. The TUI opened, listed bundles, and searched them. It was simply
answering about a *different set* than every other verb in that directory —
including the `okf registry list` a user would run to check what the TUI should be
showing. The two disagreeing is the whole failure, and neither could report it,
because each was internally consistent.

This is the shape [okf-capability-drift](/decisions/okf-capability-drift.md)
describes: okf added a resolution rule, the old call kept working, and "kept
working" meant "kept answering the wrong question".

# A third input arrived, and the answer stayed one method

okf later gained `okf registry link`: the global registry can point at another
registry file, and that file's bundles and groups resolve into the set. The TUI
needed no change to show them — `registry_entries` reads `listing` and
`registry_groups` reads `groups_listing`, and okf folds the linked half into
both. That is the point. The rule this concept states is that one question has
one answer per directory; a linked group listed by a *second* method would have
put the TUI back where it started, showing a smaller set than its own `@ref`
resolution could open, with nothing failing to say so.

What the TUI had to add for itself is that a linked bundle is **read-only**. The
config keys reached okf, which refused, and the message arrived on the status
line — correct, and too late: the user had already typed a new name or confirmed
a removal. `d`, `n`, `x` and `+` now refuse before the prompt, and the detail
pane says where the bundle comes from. That is
[registry-write-boundary](/decisions/registry-write-boundary.md)'s, not this
file's — what belongs here is only that the *set* stayed one answer.

# The library keeps okf's own line

`cwd:` is a parameter, not a default of `Dir.pwd`, and that mirrors okf exactly:
only its CLI opts in, while a library caller stays global-only. okf's reason is
that a discovered registry depends on where a *process happens to be*, which is
right for a command someone typed in a directory and wrong for an embedding app.

So `OKF::TUI::CLI` passes `cwd: Dir.pwd` and `Workspace.new` defaults to nil. The
suite depends on this too: with a default, `rake` would discover whatever registry
sat above the checkout.

Ref resolution gets discovery for free rather than separately —
`OKF::CLI::Command#open_registry` *is* `Registry.load(cwd: Dir.pwd)`, so a `@slug`
inherits the rule along with the grammar.

# Reload must reopen, not reconstruct

Every registry write is followed by a re-read, and the re-read has to be
`Registry#reopen`. `Registry.new(path)` drops the `relative_base` a discovered
local registry carries — okf hit this in its own server and wrote down the two
symptoms: every in-tree bundle reads as "folder is gone", and a bundle added
through the UI gets flattened to an absolute path, undoing the portability the
relative form exists for.

So `load_entries` discovers on the first load and reopens on every one after:

```ruby
@registry = (registry ? registry.reopen : open_registry) if registry_backed?
```

# The screen names the file

The header prints the registry path, and the "nothing to show" message names it
too. That is not decoration — it is the only way a user can tell which of the two
registries is in force, and it is what `refs_test.rb` asserts on to prove the CLI
opts into discovery at all: an empty *local* registry reports the local path,
where a run that ignored discovery would name the global one.
