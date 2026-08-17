# Frontmatter policy

| Field | Who writes it | When | Meaning |
|-------|---------------|------|---------|
| `generated: {by, at}` | An agent | At creation, always | A machine produced this. It has not been checked. |
| `verified:` (a list) | **The owner's decision** — the agent may hold the pen | Only after actually reading | Who confirmed this, and when. |
| `stale_after:` | Whoever files the concept | At creation, per the table below | The day this becomes stale — `today >= stale_after`, inclusive. Reports; never gates. |
| `sources:` | Whoever files the concept | Whenever a claim came from somewhere else | What this was derived from, and the key each claim is attributed through. |
| `status:` | Whoever settles a collision | On supersession | `draft`, `stable` (the default, so it may be left off), or `deprecated`. |

Write concepts with Edit or Write, never with a shell redirect: the
trust guards read the tool event, and a `Bash` command carries no file
path and no added text for them to see. A shell command that looks like
it writes markdown into the bundle is routed to the owner instead, and
the commit door asks git directly whether a past journal day changed —
whoever wrote it.

Both fields name an **actor**, in one of three forms: `<producer>/<version>`
for an agent, `human:<id>` for a person, `process:<id>` for an automated
check. The form is not decoration — the trust tier is read off it. A
`verified` entry whose `by` is a `human:` actor makes the concept
**human-reviewed**; entries by anything else make it **machine-confirmed**;
no `verified` key at all is **unverified**. The To-read line is cleared by
human review and by nothing else, so a nightly process confirming a briefing
does not discharge the owner's read.

```yaml
generated: { by: claude/opus-5, at: 2026-08-15T09:12:00Z }
verified:
  - { by: human:rod, at: 2026-08-15T18:40:00Z }
```

Write `verified` as a list, or as one bare `{ by, at }` mapping — those are
the two shapes the reader accepts. A **scalar** (`verified: human:rod`, or a
bare date) is not one of them, and it fails in the worst possible direction:
the guard fires on the word, so the write is routed to you for approval, and
then the reader drops the malformed value, the tier stays unverified, and the
To-read line is demanded forever. `okf validate` says so — *verified should be
a mapping or a list of mappings* — and the gate now surfaces that warning
rather than discarding it.

Concepts an agent authors carry `generated:` from creation. `verified:`
records **the owner's decision**, made only after actually reading —
for a briefing, the same event that removes its To-read line. The agent
may scribe the block, but the hooks turn that write into an explicit
owner approval, and the approval is the attestation; unattended, with
nobody to approve, the write is refused. Absent `verified:` on a
`generated:` concept is not a defect to be tidied away; it is the
truth.

Staleness windows — owned by `/areas/corpus.md`, operative here. To
change a window: record the decision in `/areas/corpus.md` first, then
update this table, then a dated `log.md` line — in that order, so the
bundle's own standard never lags the rule being applied:

| Type | `stale_after:` |
|------|----------------|
| Briefing | source date + 90d |
| Term | + 180d |
| Finding, when it reports measured external figures | + 90d |
| Learning, Decision, Journal Entry, Transcript, Overview | none |

Records don't decay; claims do. A journal entry is true forever — it
says what happened on a day. A briefing about someone else's pricing is
a claim about the world, and the world moves.

`okf lint .okf --only expired` is what answers *what has gone stale?*,
and the boundary is the format's rather than this bundle's: a concept
is stale when the day arrives, inclusive. It reports at `info` and
never gates — a date passes on the calendar, not on a change, so a gate
here would fail a morning nobody chose and the only available fix would
be to falsify a date.

