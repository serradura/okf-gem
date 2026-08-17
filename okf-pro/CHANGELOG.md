# Changelog

All notable changes to okf-pro are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this gem uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

First release. okf-pro begins as a working prototype — a checker carried inside
a template repository that was cloned to start a knowledge bundle — and becomes
a gem entered through okf's plugin seam. The template is now something `okf pro
setup` writes, rather than a repository to fork.

The prototype's surface was gates and nothing else: every verb a check, a
report, or a one-time generator. Nothing answered *what is on the board* and
nothing wrote a line, so an agent working in a seeded bundle rediscovered state
by reading raw markdown and reconstructed a line's grammar from the guides on
every use. This surface answers both.

### Added

- **`okf pro setup [DIR]`** — writes the bundle and the governance around it:
  the Claude Code hooks behind a fail-closed wrapper, a `pre-commit` hook that
  audits the *staged* tree, a CI workflow, the agent skill, `CLAUDE.md`, a
  `README.md`, a `.gitignore`, and a blank-slate `.okf/`. It writes what it can
  and never refuses wholesale: a file you already have is left alone and the
  template's version is staged beside it as `<path>.okf-pro-new`. The one thing
  it refuses outright is a directory that is *already* a bundle at its own root,
  which writing `.okf/` beside would turn into two roots the three doors
  disagree about — a bare `index.md` is a docs index, not a bundle, and is not
  refused.
  Both generated doors prove the checker's **identity** before trusting its exit
  status: a stray `okf` on PATH that exits 0 is indistinguishable from a clean
  gate, so the wrapper and the `pre-commit` hook each require the enforcer's
  marker.
- **`okf pro upgrade [DIR]`** — rewrites the four files the gem owns (the hook
  wrapper, the pre-commit hook, the workflow, the skill) and leaves every seeded
  file byte-identical. Those four carry the contract and must track the gem;
  everything else is yours from the moment it is written.
- **`okf pro hook <check>`** — one gate against one hook event on stdin.
  Eight checks plus the session banner: the attestation guard, the journal
  guard, the shell guard, conformance, the in-flight cap, reconciliation search,
  the composed post-edit pass, and the stop gate.
- **`okf pro audit [DIR]`** — every invariant at once, for CI: the closed core,
  conformance, the board's grammar, the board↔work pairing in both directions,
  and the day's snapshot. It runs the linter with a clock, so nothing is
  silently skipped, and confesses anything it still could not run rather than
  reporting clean over it.
- **`okf pro records [DIR]`** — asks git whether the staged commit rewrites a
  past journal day: a modification, a deletion, a rename or a **typechange**,
  that last being how replacing a day with a symlink hides from the first
  three. Records are append-only; corrections go in today's entry.
- **`okf pro snapshot [DIR]`** — computes the day's counter line and prints it.
  It never writes: this is a checker, not a generator.
- **`okf pro unverified [DIR]`** — the concepts still awaiting the owner's
  read, with the trust tier each one has reached.
- **`okf pro state [DIR]`** — what is on the board, in one call: every section
  counter, the budget face, deadlines nothing is in flight against, the newest
  logged day, whether today's journal is open, and the open projects. Cheap by
  contract — it reads `board.md`, `log.md` and two globs and parses no concept.
  `--full` adds the corpus-derived parts (the pairing invariants, the
  attestation list, the live unverified count) behind one bundle parse.
- **`okf pro board [DIR]`** — one row per board line: section, text, the two
  date shapes the counters read, age in days, and bundle links. `--section NAME`
  narrows it, and a section the board does not have is exit 2 rather than an
  empty answer indistinguishable from an empty section.
- **`okf pro capture "<text>"`** — a dated Inbox line, in the shape the counter
  reads. Text spanning lines is refused rather than escaped.
- **`okf pro promote <selector>` / `okf pro demote <selector>`** — a line
  between Backlog/Inbox and In flight, with the `In flight: k/CAP` header kept
  truthful in the same write. Promotion past the cap is refused, by Rule 3. A
  selector is keyed and never positional, refuses on ambiguity, and refuses a
  name that names nothing: `/` and `/projects` are directories every project
  sits under, and name none of them.
- **`okf pro journal open [DIR]`** — today's journal day and its index line.
  What goes in the day stays yours.
- **`okf pro close <project> [DIR]`** — the three mechanical closing moves: the
  marker on the project index, its board lines removed, a dated `log.md` entry.
  It names the project by its directory name or by the `/projects/<slug>/` link
  a board line carries, with or without the `index.md`. The fourth move —
  extracting the durable part to `learnings/` — is judgment, and is reported as
  owed.
- **`okf pro friction [DIR]`** — what was done by hand that a verb could do,
  recorded at two points that were already wired, and grouped by the door as
  well as the file: an Edit to the board says a verb went unused, a shell
  redirect at anything says the trust guards were bypassed. `--issue` prints a
  ready `gh issue create` against this gem's repository, and never runs it —
  and prints nothing at all when nothing was recorded, rather than a report
  whose body is an empty list; `--clear` resets a count that is otherwise a
  lifetime total. The recorder never reports a zero it did not count — a failed
  write leaves a marker, and an unwritable `.tmp/` is asked about directly. The
  session banner counts the narrower thing: only rows an `okf pro` verb would
  answer, because a shell redirect's answer is Edit or Write.
- **`okf pro skill <DEST>`** — the agent skill on its own, for a repository
  that wants the rules without the scaffold.
- **`--json` and `--pretty`** on `state`, `board`, `snapshot`, `unverified` and
  `friction`. `snapshot --json` carries the rendered line beside the twelve
  counters; `unverified --json` emits structured rows rather than prose a
  consumer would have to take apart with a regex.
- **The conservation guard.** Every write verb computes its new text purely,
  declares the delta it intends, and is refused with exit 2 — nothing written —
  if the actual delta differs, in either direction. A line dropped alongside an
  append is a refusal; so is a claimed change that never happened. `close`
  touches three files and decides about all of them before it writes any, so a
  refusal from a later move leaves the earlier ones unwritten.
- **Preconditions the guard cannot supply.** A conservation check proves a line
  was not dropped and says nothing about whether the right line was chosen, so
  the choices are guarded separately: a project name is one directory segment
  and never a relative path, `close` marks a first line only when it is a
  markdown heading (an index carrying YAML frontmatter opens with `---`, and
  appending a marker there destroys the fence while still reading as closed),
  and a writer refuses a leading dash rather than committing a mistyped flag as
  a board line — `--` escapes content that really starts with one.
- **The SessionStart banner is that state block**, carrying the same counters
  `okf pro state` prints, the last logged Snapshot line whole and labelled by
  the day it was logged under rather than as live, and a closing line saying to
  refresh with `okf pro state` instead of re-reading the files. Nothing in it is
  said twice: state delivered without costing a turn is still state a reader has
  to get through.
- **A seeded `README.md`, written for the owner rather than the agent.**
  `CLAUDE.md` and the skill both address the agent; this is the only file in the
  generated tree that addresses the person, so it carries what the skill never
  will — a week showing the system in use, the four habits it structures, the
  tunable numbers and where they live, how to turn each gate off, what survives
  removal, and what the layer does not promise. It is agent-first by
  construction: the reader talks to their agent and the verbs appear in one late
  section, because an owner can go a week without typing one. Seeded, not
  gem-owned, so `upgrade` never touches it.
- **The skill routes to the CLI before it routes to a guide.** `SKILL.md` opens
  its "What to load" section with a table of what to run instead of what to
  read, and carries the canonical line shapes inline — the board bullet, the two
  date grammars, the conflict line, the closure marker. The prototype named
  `audit` and `unverified` only in `guides/okf-rules.md`, which the index routes
  to *after* something has broken, and they went unused for exactly that reason.

### Changed from the prototype

- **The trust policy is OKF v0.2's.** "Awaiting the owner's read" is derived
  from §5.3's trust tiers rather than from a truthiness test on `verified:`.
  A `human:<id>` verification discharges the read; a `process:` or agent one
  makes the concept *machine-confirmed* and leaves the read owed.

  **Migration:** `Snapshot`'s `unverified briefings` counter changes meaning, and
  the stop gate verifies that counter field by field — so every `**Snapshot**`
  line written under the old rule will be reported as disagreeing with its board.
  Recompute the current day's line with `okf pro snapshot .`; past days are
  records and stay as they are.

  **Migration:** `verified:` must be a mapping or a list of mappings, and its
  `by` must use the §7 actor convention (`human:rod`, not `rod`) to count as a
  human review. A scalar `verified:` now surfaces the validator's warning
  instead of being silently dropped.
- **`freshness` is removed.** `stale_after` is the format's own field and §5.5
  owns where its boundary falls — a concept is stale when `today >= stale_after`,
  inclusive, which is a day later than the prototype's own comparison.
  `okf lint --only expired` answers the question, once, correctly.
- **The gate no longer reports clean over checks it did not run.** A default
  lint skips `expired` and `stale`; the clock is now supplied so `expired` runs,
  `stale` is excluded in source with its reason, and anything okf reports as
  skipped in future is surfaced rather than discarded.
- **Both doors surface `okf validate`'s warnings.** They read only the errors,
  so every soft finding — including a malformed trust block — was dropped. The
  hook door reports them on every Edit and Write, and `okf pro audit` counts
  them as findings, exactly as it already counted a linter warning: a
  conformant-but-malformed `verified:` is caught at the agent's tool boundary,
  and must not then be waved through by the two doors an edit made in an editor
  actually passes.
- **`status: deprecated` is operative.** A reconciliation hit on a concept that
  is already deprecated says so, instead of inviting the collision to be
  re-litigated.
- **The shell guard no longer reads an ASCII arrow as a redirection.** `>` was
  matched anywhere in a command while the comment above the pattern claimed it
  was anchored to a position a redirection can occupy. Nothing implemented
  that, so `grep -rn "a --> b" .okf/` — a read — was routed to the owner as a
  suspected write, as was every grep for a `<!-- rule: … -->` marker or a quoted
  Ruby hash. A guard that fires on reads trains the reflex that approves the one
  prompt that mattered.
- **The rules stop asking for redundant conformance runs.** The PostToolUse
  hook runs `okf validate` and `okf lint` in process on every Edit and Write;
  `guides/okf-rules.md` says so, and asks for a manual run only when you need
  the detail behind a refusal.
- **The Ruby floor is 2.4**, okf's own, down from the prototype's 2.7. This code
  runs in git hooks and CI steps on machines nobody chose.
- **The `.bin/okf_pro` binary is gone.** `okf pro` is the only door, which is
  what lets the wrapper refuse anything that is not it.
