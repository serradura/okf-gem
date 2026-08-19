---
type: Component
title: The Rendering Layer
description: Six screens built as rows of text with no terminal I/O, over primitives that measure and cut strings by display width rather than by character count.
tags: [structure, rendering, ansi, layout]
timestamp: 2026-08-19
---

# The files

| file | pure? | what it owns |
|---|---|---|
| `lib/okf/tui/views.rb` | pure | the six screens — row builders, no terminal I/O |
| `lib/okf/tui/ui.rb` | pure | layout primitives: width, clipping, wrapping, boxes |

Both are pure, and that is the property the test suite is built on: a view
returns an array of strings, so a test can assert a frame without a pty.

# Views: one builder per screen, plus the chrome

`Views` is a module of builders taking `(app, width, height)` and returning rows.
Beyond the six screens it owns the chrome every screen wears — `header`,
`workspace_header`, `tabs`, `footer`, `active_badge` — and the two vocabularies
that must be identical everywhere: `TYPE_COLOURS` / `type_colour`, and `STATUS` /
`health_status` / `status_style`.

That second one is the point of [status-vocabulary](/rendering/status-vocabulary.md):
`validate` and `lint` collapse into **one** verdict so a problem is visible from
any view, rather than only from the one that ran the check.

`pair` is the label/value row every detail panel is made of, and it is worth
reusing rather than re-aligning by hand.

# Ui: nothing here counts characters

`String#length` is the wrong answer twice over — a wide CJK glyph occupies two
columns, and an ANSI escape occupies none — so every primitive here measures
display width instead. `ANSI` is the escape pattern, `width` the measure, and
`clip` / `clip_ansi` / `wrap_ansi` / `reflow` the cuts that respect it.
[ansi-aware-width](/rendering/ansi-aware-width.md) is the arithmetic and why the
geometry suite runs twice.

`TABULAR` exists because a box-drawing run must not be reflowed as prose, and
`LIST_START` because a bullet's continuation lines have to hang under its text.
`reset_if_styled` closes a style at the end of a row so a colour cannot bleed
into the next one — a frame is printed whole, so one unterminated sequence
stains everything below it.

`Line` is the builder for a single row under a width budget; `blank_line`,
`fit_block`, `hjoin`, `box` and `title_label` compose them. `PASTEL` is
constructed once, with `FORCE_COLOR` honoured, because colour detection is a
terminal question and the tests need to answer it themselves.

The trap that only appears with colour on is
[markdown-rendering-trap](/rendering/markdown-rendering-trap.md); read it before
touching anything that hands a width to tty-markdown.
