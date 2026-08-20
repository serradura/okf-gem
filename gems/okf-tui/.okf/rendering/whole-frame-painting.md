---
type: Component
title: Whole-frame Painting
description: Each keystroke repaints every row from cursor-home rather than diffing, which makes a frame a pure function of state and is what lets the tests render without a terminal.
tags: [rendering, terminal, testing]
generated:
  by: human:maintainer
  at: 2026-07-18
sources:
  - title: "`lib/okf/tui/app.rb` — `paint`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/app.rb
  - title: "`test/test_helper.rb` — `FixedScreen`, `frame_for`, `render`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/test_helper.rb
---

# Overview

There is no damage tracking, no dirty-region diffing, and no partial redraw.
`paint` moves the cursor home and prints exactly `height` rows, every time.

For a screen of this size the redraw is imperceptible, and buying simplicity with
it is a good trade — but the real payoff is not performance, it is testability.

# Why it makes the UI testable

Because painting reads state and writes a string, a frame is a **pure function of
(workspace, keys, size)**. Nothing about it needs a terminal:

```ruby
app = App.new(dirs: [...], output: StringIO.new)
FixedScreen.with(width, height) { keys.each { |key| app.handle(key) } }
```

`handle` mutates state exactly as the key loop does, and `paint` renders it into
a `StringIO`. So the tests drive real interactions and assert on real frames
without a pty — see [headless-frames](/testing/headless-frames.md). A diffing
renderer would have made the output depend on what was on screen *before*, and
that property would be gone.

The terminal size is the only ambient input, so `FixedScreen` pins it by
prepending an override onto `TTY::Screen` — otherwise a frame would render
differently on the machine running the suite.

# The consequences to respect

- **Every row must be exactly the width** — nothing repairs a short row on the
  next pass, because there is no next pass until a key arrives. See
  [ansi-aware-width](/rendering/ansi-aware-width.md).
- **The frame must fit the height** — a view that builds more rows than the
  terminal has scrolls its own content; it never lets the frame overflow. Health,
  graph and help each build the full page and scroll it, which replaced an
  earlier per-pane budget that could go negative on a short terminal and crash.
- **Views stay pure row builders.** No view writes to the terminal; they return
  arrays of rows. The app is the only thing that prints.
