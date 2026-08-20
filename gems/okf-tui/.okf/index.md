---
okf_version: "0.2"
---

# okf-tui knowledge bundle

The knowledge behind **okf-tui** — the full-screen terminal UI over
okf (`@okf`) bundles. It is written to be read *before* opening `lib/`, so an
agent about to add a view, a key or a panel does not re-derive the layering and
does not rebuild something the kernel or this program already answers.

`AGENTS.md` beside it carries the contracts a change has to keep and routes here
for everything else; the `README` is the user's. What used to be a
hand-maintained Map of `lib/**` in `AGENTS.md` now lives in
[Structure](structure/), pinned by `test/unit/bundle_catalog_test.rb` — the code
is the truth and this bundle is the claim, so the two cannot drift quietly.

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

* [Structure](structure/) - Every file under `lib/`, grouped by the layer that owns it: the doors, the workspace and the model, the app, and the rendering layer.
* [Capabilities](capabilities/) - The catalogue: the six views and the kernel surface behind them, before you build a seventh.
* [Decisions](decisions/) - The choices and their tradeoffs: the analysis boundary with okf, the search facade and the branch it outlived, the inherited Ruby floor, and why no dependency carries a ceiling.
* [Interaction](interaction/) - The keyboard model — key routing and its modes, Esc as a stack, submitted rather than live search, following a link out of the page, and the two independent axes of "which bundle".
* [Rendering](rendering/) - Composing a frame: ANSI-aware width, whole-frame painting, the tty-markdown trap that only appears in colour, and the one verdict a bundle wears everywhere.
* [Testing](testing/) - Frames proven without a terminal, the single pty walk that proves the binary boots, and the CI matrix that catches what a local run structurally cannot.
