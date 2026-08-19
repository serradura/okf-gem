---
type: Finding
title: The eight failure modes
description: The named ways a personal knowledge system dies — three by lying and five by telling the truth badly — and the mechanism that answers each.
generated:
  by: human:maintainer
  at: 2026-08-17
---

# The catalogue

Every rule in this design exists because one of these demanded it. None is
hypothetical.

| # | Failure | Closed by |
|---|---------|-----------|
| 1 | **The Flood** — weeks without triage, and the tidy view cannot signal its own incompleteness | the snapshot delta: inbox count and oldest age, read against yesterday's line |
| 2 | **Contradiction Cascade** — Monday's doc says X, Wednesday's thread Y, Friday's ticket Z, all fresh, all verified | triage as a read before a write; capture the decision's timestamp, not the artifact's |
| 3 | **Cross-Cutting Meeting** — a meeting kills a project offscreen and the absence of a link is invisible | triage asking *what does this make untrue?*, not only *where does this belong?* |
| 4 | **Ghost Project** — a deprioritised project never closes and crowds the view | dormancy, derived from journal links: still in flight, or backlog pretending? |
| 5 | **The Liar** — a misheard number, captured and verified: maximum trust, false claim | not closable — [the residue](/design/the-residue.md). Mitigated by the source pointer |
| 6 | **Amnesia Week** — journal completeness inversely correlates with workload | declared reconstruction: rebuild from `log.md` and git history, and say in the entry that you did |
| 7 | **Agent Drift** — an LLM regenerating a view drops a task silently | the checker/generator split, plus the conservation guard where a verb does write — [derivation-that-writes](/design/derivation-that-writes.md) |
| 8 | **Priority Inflation** — everything becomes priority one and priority stops carrying information | the cap: promotion requires demotion, and position replaces priority syntax |

# The split that matters

Three of these are the system **lying** — 2, 3 and 5. Provenance and
reconciliation close them.

The other five are the system **telling the truth badly**: incomplete, noisy,
inflated, thin. Not one false statement between them, and the terminal state is
identical — you stop reading it. That is the finding the design is built on:
**attention, not truth, is the scarce resource**, and no frontmatter field ever
fixed an attention leak. It is why the laws are behavioural.

# The same standard, applied to the gates themselves

The enforcement layer is held to this from the other side, and its own bug
history says why: every defect it has produced failed open *while looking like
it had run* — a missing parser, a misspelled variable, a rescued error, a wrong
event shape, a stray binary on PATH. Silent incompleteness is failure mode 1
wearing the checker's uniform, which is why the gates refuse on their own
absence ([contract/the-contract](/contract/the-contract.md)) and why the suite
is weighted toward the degraded paths
([testing/drills-over-units](/testing/drills-over-units.md)).
