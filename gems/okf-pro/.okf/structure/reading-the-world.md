---
type: Component
title: Reading the world — the root, the event, and the two documents as data
description: Six files that answer where the bundle is, what arrived on stdin, and what `board.md` and `log.md` say — before any gate has an opinion.
---

# The files

| file | pure? | what it owns |
|---|---|---|
| `lib/okf/pro/bundle_root.rb` | pure | where the bundle is, given where the agent is |
| `lib/okf/pro/event.rb` | pure | the hook event — the only place untrusted input is parsed |
| `lib/okf/pro/target.rb` | shell | bundle root + edited path, or `nil` when a check cannot apply |
| `lib/okf/pro/board.rb` | pure | `board.md` as data: sections, budget header, links, dates |
| `lib/okf/pro/log.rb` | pure | `log.md` as data: the snapshot line, the newest day |
| `lib/okf/pro/records.rb` | shell | the append-only record, asked of git at the commit door |

# Where the root is

`BundleRoot.resolve` walks from a starting directory to the bundle it belongs
to. `DIR` is `.okf`, and `root_kind` distinguishes the repository root from a
level root from a plain directory, because "the bundle" is a different question
in a monorepo than in a repository holding one. It is the one reader that does
**not** go through `read_contained`: it is deciding where the root *is*, so it
has none to contain against — a raise there would be a permanent lockout and a
rescue would mis-root the bundle and disarm the journal guard.

# What arrived

`Event` is a class rather than a module, and it is the only place untrusted
input is parsed. It answers `tool_name`, `tool_input`, `file_path`, `command`,
`cwd`, `added_text`, `stop_hook_active?` — and `parse_error?`, which is the
honest answer to malformed JSON rather than an exception thrown at a gate that
would then not run.

`Target.for(event)` turns an event into a root plus a relative path, or `nil`
when the check simply does not apply — an edit outside any bundle is not a
failure, and a gate that treated it as one would refuse every edit in the
repository. `Target#read` and `#exist?` are how a gate reaches a file inside
its own root.

# The two documents

`Board` and `Log` are the parsers, and they are pure — no disk, no stdio.

`Board` strips HTML comments first (`strip_comments`, then `visible`), because
a commented-out row is not on the board and every count downstream depends on
that being true. It answers `rows`, `count`, `budget`, `targets`, `line_date`,
`chase_date`, and the three grammar checks — `missing_sections`,
`date_findings`, `stray_bullets` — against the six `SECTIONS` it knows.

`Log` answers the questions the closing gate asks of `log.md`:
`snapshot_under?` for a given day, `days`, `newest_day`, `latest_snapshot_entry`,
and `malformed_days`. `DAY_HEADING` and the deliberately looser `DAYISH_HEADING`
exist as a pair — the second is how a heading that *looks* like a day but is not
one gets reported instead of silently skipped.

The gates that consume all six are [the-gates](/structure/the-gates.md).

`Records` is the git question: `staged_violations` asks the index, not the
working tree, whether a commit rewrites or deletes a past journal day. It is at
the commit door because that is the only door where the staged tree is the truth.
