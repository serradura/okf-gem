# Board anatomy

`board.md` is the only cross-work view: the entire commitment surface
on one bounded page. Sections, in this order:

* **In flight** — one *next-action* line per demand. One line, not the
  list: the full outstanding list stays in the project's own
  `index.md`, because a board that carries every step is a project plan
  wearing a board's clothes, and it stops being readable at a glance.
* **Backlog** — captured, real, and not started. No next action yet;
  writing one is part of promoting it.
* **Waiting** — who / what / when asked / chase date, the last written
  literally as `chase YYYY-MM-DD`. This is the class
  that rots silently: nothing here fails loudly, it just quietly never
  arrives, and the chase date is the only thing standing between a
  dependency and a month of drift.
* **Inbox** — dated capture lines — `- YYYY-MM-DD — <the words you
  heard>` — five seconds each, with an optional one-sentence gist. Not a filing
  decision — capture is cheap precisely because it defers filing.
  Conflict lines from Rule 1 (in [SKILL.md](../SKILL.md)) live here too:
  an unsettled contradiction is undifferentiated work until someone
  triages it.
* **To read** — documents shared with you. Reading *is* the action, and
  only reading takes the line away; a briefing an agent summarised is
  not read, and its line stays.
* **Deadlines** — dates in the world, one per line, the date first:
  `- YYYY-MM-DD — <what lands>`. They arrive whether or not anyone
  acts, so they sit explicitly outside the pipeline and outside the cap.

The dates are grammar, not style, and so is the bullet. Board lines
start `- ` at column zero — a `*` bullet or an indented dash is a line
no counter can see, including the cap. The counters read exactly three
date shapes — a leading `- YYYY-MM-DD` on Inbox and Deadlines lines, a
literal `chase YYYY-MM-DD` on Waiting lines — and a date in any other
spelling parses to nothing. Rather than let any of that count as a
quiet zero (a deadline the 7-day warning cannot see is a deadline that
lands unclaimed), the audit and the stop gate flag the unreadable line.
HTML comments are not board content when they keep to their place: a
comment is `<!-- ... -->` balanced on one line, anywhere on the line,
and a longer note is a stack of single-line comments. Any `<!--`
without its `-->` on the same line hides nothing and is flagged —
comment-intended text must not feed the counters in silence.

A section earns its own file only when it stops being bounded (it no
longer fits on the page) or stops flowing (lines arrive and never
leave). Until then: one page, atomic edits, and `git log board.md` is
the state timeline nobody had to maintain.

The board is state, not a concept — but OKF exempts only `index.md` and
`log.md` from the frontmatter rule, so it carries a minimal block with
`type: Board`. That is the ninth type, and its reason is exactly this:
the format requires a declaration, and the board is none of the other
eight. Read the frontmatter as a conformance receipt; the page below it
is the whole point.

