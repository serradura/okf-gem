# OKF rules

* Every `.md` except `index.md` and `log.md` carries YAML frontmatter
  with a non-empty `type`, `title` and `description`.
* Directory `index.md` files carry **no** frontmatter and list every
  concept in their directory. The root `index.md` carries `okf_version`
  and nothing else — `okf_version: "0.2"`.
* One concept per file.
* Links are absolute and bundle-relative: `/reference/thing.md`.
* After any change: update the directory index and add a dated `log.md`
  entry.
* **Do not run `okf validate` and `okf lint` after every edit.** The
  gates run themselves — the PostToolUse hook runs both, in process, on
  every Edit and Write, and refuses with what they found. Running them
  by hand afterwards re-reads a bundle that has already been read and
  re-answers a question already answered. Run them when you need the
  *detail behind a refusal*, or when you edited outside the agent's
  tools; otherwise the gate has it.
* The gates are also runnable by hand when you want the answer before
  the refusal: `okf pro audit .` runs every invariant at once, `okf pro
  state .` says what is on the board, `okf pro unverified .` lists what
  still awaits the owner's read, and `okf pro snapshot .` computes the
  day's line. None of those writes anything.
* Scratch work goes under `.tmp/` at the repository root, outside the
  bundle entirely.
