---
type: Decision
title: The Undeclared Width Dependency
description: Ui.width rests on unicode-display_width, which arrives through tty-box rather than the gemspec — accepted deliberately, and guarded by a test that fails loudly if it stops arriving.
tags: [dependencies, rendering, terminal]
generated:
  by: human:maintainer
  at: 2026-07-19
sources:
  - id: "1"
    title: "Sabotage run 2026-07-19: `Ui.width` reduced to `plain.length`, both checks failed as predicted, then restored — 38 runs green."
    resource: "Sabotage run 2026-07-19: `Ui.width` reduced to `plain.length`, both checks failed as predicted, then restored — 38 runs green"
  - title: "`lib/okf/tui/ui.rb` — the guarded require and the fallback."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/ui.rb
  - title: "`test/integration/geometry_test.rb` — `WIDE_STATES` and the display-columns check."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/integration/geometry_test.rb
---

# Overview

[Column measurement](/rendering/ansi-aware-width.md) is the invariant the whole
layout rests on, and it is computed by a gem the gemspec does not name:

```ruby
begin
  require "unicode/display_width"
rescue LoadError
end
...
if defined?(Unicode::DisplayWidth)
  Unicode::DisplayWidth.of(plain)
else
  plain.length          # the fallback
end
```

It loads today because `tty-box` depends on it transitively. So the most
load-bearing measurement in the program is held up by another gem's dependency
graph.

# Why it stays that way

Declaring it was the obvious fix and was deliberately declined: the gem is
already installed for every user, nothing changes for anyone today, and the
guarded `require` means the program degrades rather than crashes.

The accepted risk is narrow and worth naming precisely. If `tty-box` ever drops
`unicode-display_width`:

- nothing crashes — the `rescue LoadError` swallows it;
- ASCII keeps rendering correctly — the fallback counts characters, which is the
  right answer for ASCII;
- **CJK, emoji and combining marks start shearing the frame**, and only there.

So the failure is silent, partial, and shows up in a user's terminal rather than
in CI. That combination is why it needed a guard even though it needed no
gemspec line.

# What guards it

Two checks, and the split between them is the point:

| Check | Catches |
|-------|---------|
| the `wide` fixture rendered at four sizes | the shear itself, end to end |
| `Ui.width("日本語") == 6` plus `assert defined?(Unicode::DisplayWidth)` | the gem going missing |

The second is deliberately **not** a rendering assertion. Were the gem to vanish,
the layout and any test measuring through `Ui.width` would both fall back to
counting characters and would agree with each other — passing while the real
terminal sheared. A test that degrades alongside the code it checks is not a
guard.

Both were verified by forcing the fallback: a row measured 87 columns in an
80-column terminal, and CJK measured 3 instead of 6.[^1]
