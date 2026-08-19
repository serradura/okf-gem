---
type: Component
title: The App — State, the Key Loop, and the Frame
description: "One class holding the whole session: which view, which selection, which prompt is open, and the loop that reads a key, changes that state, and repaints every row."
tags: [structure, keyboard, state, terminal]
generated:
  by: human:maintainer
  at: 2026-08-19
---

# The file

| file | pure? | what it owns |
|---|---|---|
| `lib/okf/tui/app.rb` | shell | state, the key loop, frame painting |

It is the largest file in the gem and the only one that reads a keystroke, and
those two facts are the same fact: everything that is *not* state or input has
been pushed down into `Views` and `Ui`, or out into `Workspace` and `Model`.

# The tables that define the surface

| constant | what it fixes |
|---|---|
| `TABS` | the six views, in the order the tab bar shows them, `help` last |
| `KEY_VIEWS` | `1`–`6`, the direct jump to each |
| `SINGLE_BUNDLE_VIEWS` | `browse`, `health`, `graph` — the ones with nothing to show when no bundle can be read |
| `CONTENT_VIEWS` | `health`, `help` — a scrolling page rather than a selectable list |
| `FILTERABLE_VIEWS` | `bundles`, `browse`, `graph` — the ones `/` narrows |
| `PANES` | `bundles`, `groups`, `members` — what Tab cycles inside the bundles view |

There were seven views once. The `index` map went because browse answers the
same question with a key the reader already has, and what the map could show and
browse cannot is real but narrow. A seventh tab is a real cost on a six-tab bar.

`Prompt` is a pending question on the status line: `kind` decides what the answer
does, and `free_text?` says whether it collects a line or a single confirming
key. Every destructive registry action goes through one.

# The loop, and why the frame is a pure function

`run` reads a key, routes it, and calls `paint`. `paint` moves the cursor home
and prints exactly `height` rows — no damage tracking, no dirty regions. That is
what makes a frame a pure function of state, which is in turn what lets the whole
test suite render without a terminal
([headless-frames](/testing/headless-frames.md)).

Key routing has modes, and Esc peels one layer at a time rather than quitting
outright — both arrived at by getting them wrong first:
[key-routing](/interaction/key-routing.md),
[esc-peels-one-layer](/interaction/esc-peels-one-layer.md).
`/` starts a filter, and the filter belongs to the *view*, so switching away
drops it rather than carrying a bundle filter into the concept list; where the
filter runs out, [filter-escalates-to-search](/interaction/filter-escalates-to-search.md)
is what happens next.
