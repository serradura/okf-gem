---
type: Component
title: The Analysers — Validate and Lint, Kept Apart
description: Two pure analysers with a boundary that is a spec requirement rather than a preference — conformance may not reject curation problems, and curation may not emit conformance errors.
tags: [structure, validate, lint, pure, spec]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/bundle/validator.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf/bundle/validator.rb` | §11 conformance: hard errors, plus soft convention warnings |
| `lib/okf/bundle/validator/result.rb` | the errors/warnings collection and `valid?` |
| `lib/okf/bundle/linter.rb` | the curation report — every check, and their severities |
| `lib/okf/bundle/linter/report.rb` | findings by severity, the stats, and `healthy?` |

# The boundary is the point

**`validate` and `lint` stay separate**, and the line is the spec's, not taste.
§11 forbids the validator from *rejecting* a broken cross-link or a missing
optional field — those are warnings at most. Curation findings belong to lint,
which never emits a conformance error.

A new check goes to one side or the other, and getting it wrong changes what
exit code a user's CI sees: 0 ok, 1 a failing bundle, 2 a usage error.

`Validator::CONVENTION_CHECKS` is the soft half — the warnings that are about
convention rather than conformance, so a caller can tell them apart.

# Validator: one method per spec clause

The private methods are named for what they check — `validate_families`,
`validate_generated`, `validate_verified`, `validate_sources`,
`validate_usage_window`, `validate_lifecycle`, `validate_computation`,
`validate_parameters`, `validate_contract_mapping`, `validate_okf_version`,
`validate_index`, `validate_log`, `validate_reserved`, `validate_unparseable`.
A new §5 family is a new one of these; that is the shape to follow.

`validate_unparseable` is the one worth noticing: a file the reader could not
parse is an error, not an absence. A validator that skipped it would report
clean over the file most likely to be broken.

# Linter: severities are data, and downstream depends on them

`SEVERITIES` is the whole check list with each check's level, and `CHECKS` is
its keys. It is a public fact rather than an implementation detail — okf-pro
pins a frozen snapshot of it, because a released kernel that reclassified a
check would change what that gem's gate blocks on.

`only:` and `except:` select checks; `stale_before:`/`today:` supply the clock
that `expired` and `stale` need. **A check that could not run is reported, not
dropped**: `Report#to_h` carries `skipped_checks`, and `healthy?` over a silent
skip would be the same lie in a smaller box.

`DEFAULT_MIN_BODY` and `HUB_LIMIT` are the two tunables; `ACTOR_FORMS` is the
`generated.by` grammar, shared with the validator through `Concept`.
