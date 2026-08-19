---
type: Component
title: ANSI-aware Width
description: Every layout primitive measures display width on colour-stripped text, because String#length counts escape bytes and a composed frame breaks the moment those two disagree.
tags: [rendering, terminal, ansi]
generated:
  by: human:maintainer
  at: 2026-07-19
sources:
  - title: "`lib/okf/tui/ui.rb` — the primitives."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/lib/okf/tui/ui.rb
  - title: "`test/integration/geometry_test.rb` — the two-colour matrix and `with_colour`."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/test/integration/geometry_test.rb
---

# Overview

The whole composition rests on one invariant: **every painted row measures
exactly the terminal width.** A row that measures wide pushes the frame's right
edge into the next line and the layout shears; a row that measures narrow leaves
the box unclosed.

Colour is what makes this hard. `"\e[31mred\e[0m"` is 3 characters on screen and
14 in `String#length`, so any primitive that pads, clips, or wraps using
`#length` is wrong the moment styling is applied — and wrong *invisibly*, because
the arithmetic is self-consistent.

Every primitive in `Ui` therefore measures on the ANSI-stripped text and operates
on the styled one:

| Primitive | Does |
|-----------|------|
| `Line` | builds a row, tracking `@spent` in display columns |
| `clip_ansi` | truncates to N columns without cutting an escape in half |
| `wrap_ansi` | wraps at display width, carrying style across the break |
| `reflow` | rejoins paragraphs, then wraps them |
| `fit_block` | pads **and truncates** a block to exact height and width |

# The test has to run twice

Pastel disables colour when stdout is not a terminal. So a captured frame in a
test is **uncoloured**, which exercises none of the code above — the geometry
suite would pass while every coloured path was broken.

`GeometryTest` therefore runs the whole matrix twice, swapping the `PASTEL`
constant for a `Pastel.new(enabled: true)` instance on the second pass: 20
interaction states × 4 terminal sizes × 2 colour modes. That doubling is not
thoroughness for its own sake; it is the only pass that tests the ANSI
arithmetic at all.

`fit_block` originally padded but never truncated, which is precisely the bug
this catches: markdown longer than the pane overflowed and wrapped the frame.

The invariant exists because nothing
[repairs a bad row later](/rendering/whole-frame-painting.md) — the frame is
printed whole and then not touched until the next keypress. And the doubling is
not paranoia: a bug that lives *only* in the coloured path is exactly what
[the tty-markdown trap](/rendering/markdown-rendering-trap.md) turned out to be.

# And a third time, on text where a character is not a column

The matrix above asserts each row's *stripped length* equals the width — which
is only a width assertion on ASCII, where characters and columns are the same
number. Every fixture was ASCII, so all 6,240 of those assertions passed
identically whether the layout measured columns or characters. They could not
tell the two apart.

The `wide` fixture is the case that can: CJK is two columns per character, emoji
two, a combining mark zero. Six states render it at the same four sizes in both
colour modes, measured with `Unicode::DisplayWidth` **directly** rather than
through `Ui.width`, so a regression in `Ui` cannot be validated by a test using
the same broken measure.

Which matters because `Ui.width` depends on a gem nobody declared — see
[the undeclared width dependency](/decisions/undeclared-width-dependency.md).
