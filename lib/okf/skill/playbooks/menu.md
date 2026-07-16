# Playbook: menu — "what should I do?" the no-argument front door

Reached when `/okf:gem` (or the skill) runs with no verb and no task. Do not
guess a workflow and do not run one on your own: **orient on the signals, then
recommend the two or three highest-value moves and let the user pick.** The full
Commands table in [SKILL.md](../SKILL.md) is the fallback menu; the recommendation
is the lede.

1. **CLI present?** `okf --version`. If it is missing, the only useful move is
   setup: follow [doctor.md](doctor.md) (install and verify the CLI) and stop
   here. Everything below needs the CLI.
2. **Bundle present?** Locate one: the directory you were given, else a `.okf/`
   directory or a root `index.md` whose frontmatter carries `okf_version`.
   - **No bundle** → when the target (or an obvious docs directory) already
     holds markdown documentation, lead with **`migrate`** (OKFy it in place —
     frontmatter on, bodies verbatim); otherwise lead with **`produce`**
     (create the first bundle from the code, docs, or what lives only in
     people's heads). Nothing else applies yet.
3. **Read the bundle's state** from the CLI, not by eyeballing:
   `okf validate <root>`, `okf lint <root>`, `okf loose <root>` — the plain
   text views, which are lighter than `--json` when you are reading a report
   rather than extracting structure from it. Then recommend by what they
   report, most-blocking first:
   - **`validate` has errors** → lead with **`curate`**: §9 conformance errors are
     the only hard failures, and curate fixes them before anything else.
   - **clean `validate`, but `lint`/`loose` findings** → lead with **`curate`** to
     settle the curation debt (reachability, backlog, completeness, hygiene),
     naming the top one or two categories from the report.
   - **clean across the board** → the bundle is healthy, so lead with **`consume`**
     (put it to work on the task at hand) — or **`search`** when what the user
     actually has is a question ("what do we know about X?") — and offer
     **`maintain`** as the move for when the code or docs have since changed. If
     the working tree has uncommitted changes to the code the bundle describes
     (`git status`), prefer **`maintain`**: that is exactly the drift it exists
     to close.
4. **Freshness is off by default.** If the bundle carries timestamps, note that a
   plain `lint` said nothing about staleness and `okf lint <root> --stale-after
   90d` is the check that would.

Keep it to two or three pointed picks, each with the exact `/okf:gem <verb>` to
run and a one-line reason from the signals. Never auto-run a workflow from here.
