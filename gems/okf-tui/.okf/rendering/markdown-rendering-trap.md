---
type: Reference
title: The tty-markdown Wrapping Trap
description: tty-markdown raises IndexError on some documents when colour is on, so the renderer asks it never to wrap and does its own wrapping instead.
tags: [rendering, terminal, ansi, scar-tissue]
timestamp: 2026-07-18
---

# The symptom

Some concepts rendered as a red error instead of a body. Not all of them, and not
reproducibly from a test or a screenshot — 50 of 192 concept/width pairs failed.

```
IndexError: index N out of string
```

# The cause

`tty-markdown` wraps text through the `strings` gem, which miscounts ANSI escape
sequences and can compute an insert position past the end of the string. It only
happens **with colour on**, which is why nothing caught it: Pastel disables
colour when stdout is not a terminal, so every piped test run and every captured
screenshot rendered the same documents fine. The bug lived exclusively in the
interactive path.

# The fix

Take the wrapping away from tty-markdown entirely. It is asked to parse at a
width no document reaches, and the layout's own
[ANSI-aware wrapping](/rendering/ansi-aware-width.md) does the real work
afterwards:

```ruby
PARSE_WIDTH = 10_000

mode = Ui.pastel.enabled? ? :always : :never
Ui.reflow(TTY::Markdown.parse(source, width: PARSE_WIDTH, color: mode).lines, limit)
```

Two details matter and neither is decoration:

- **`PARSE_WIDTH = 10_000`** — large enough that tty-markdown never reaches a
  wrap decision, so the miscounting code never runs.
- **explicit `color:`** — tty-markdown otherwise makes its own colour decision,
  which can disagree with Pastel's and produce escapes the layout did not expect.

The rescue around the render now includes the exception *message*, not just the
class. The original error surfaced as a bare class name, which said nothing about
where to look.

# The lesson worth keeping

A rendering bug that only appears with colour on cannot be caught by any test
that captures output through a pipe. When a screen misbehaves in the terminal but
not in a test, **suspect the colour path first** — it is the one the harness
never walks.

# Citations

[1] `lib/okf/tui/app.rb` — `PARSE_WIDTH` and the render.
[2] Reproduced by sweeping every concept × width with colour forced on: 50/192
    raised `IndexError`; 0/192 with the fix.
