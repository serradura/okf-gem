---
okf_version: "0.1"
---

# okf-tui knowledge bundle

The non-obvious knowledge behind **okf-tui** — the full-screen terminal UI over
[okf](@okf) bundles. The `README` documents what the six views answer and which
keys drive them, and `AGENTS.md` carries the contracts a change has to keep; this
bundle deliberately restates neither.

What it captures is what the code cannot tell you on its own: *why* the
interaction model is what it is (each piece of it arrived at by getting it wrong
first), the terminal-composition arithmetic that breaks the moment colour is
involved, the coupling to an okf API and the scaffolding that outlived it, and
what each layer of the test suite can and cannot catch.

The through-line, if there is one: **this program invents no analysis.** okf owns
every judgement on screen, so the knowledge worth recording here is not what the
bundles say — it is how a screen shows them without lying, and where doing that
turned out to be harder than it looked.

# Areas

* [Decisions](decisions/) - The choices and their tradeoffs: the analysis boundary with okf, the search facade and the branch it outlived, the inherited Ruby floor, and why no dependency carries a ceiling.
* [Interaction](interaction/) - The keyboard model — key routing and its modes, Esc as a stack, submitted rather than live search, following a link out of the page, and the two independent axes of "which bundle".
* [Rendering](rendering/) - Composing a frame: ANSI-aware width, whole-frame painting, the tty-markdown trap that only appears in colour, and the one verdict a bundle wears everywhere.
* [Testing](testing/) - Frames proven without a terminal, the single pty walk that proves the binary boots, and the CI matrix that catches what a local run structurally cannot.
