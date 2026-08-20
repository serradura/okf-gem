# Rendering

How a frame is composed, and the arithmetic that breaks when colour is involved.

* [ANSI-aware Width](ansi-aware-width.md) - Display width versus `String#length`, the primitives that respect it, and why the geometry suite runs twice.
* [Whole-frame Painting](whole-frame-painting.md) - Repaint everything each keystroke; the purity that buys, and the constraints it imposes.
* [The tty-markdown Wrapping Trap](markdown-rendering-trap.md) - An `IndexError` that only appears with colour on, and the parse width that avoids it.
* [One Verdict, Worn Everywhere](status-vocabulary.md) - Collapsing `validate` and `lint` into one colour so a problem is visible from any view.
* [A layout that cannot fit says so](fit-or-say-so.md) - Two panes or one, the same key either way, and a new split judged by its narrowest column rather than by how it looks now.
