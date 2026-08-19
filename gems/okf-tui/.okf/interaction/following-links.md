---
type: Decision
title: Following a Link Out of the Page
description: The picker is a mode rather than inline hints, the directory link okf declines to resolve, and the count it deliberately disagrees with.
tags: [ux, keys, okf-coupling]
timestamp: 2026-07-19
---

# Overview

`f` lists the markdown links leaving the open document; `1`–`9` or `Enter`
follows one. The list comes from `OKF::Markdown::Links` — the same extraction
`Bundle::Graph` builds its edges with and the validator warns on — so this walks
the graph okf already computed rather than reading the body for link syntax. It
stays inside [invents-no-analysis](/decisions/invents-no-analysis.md) by asking,
not parsing.

# A picker, not inline hints

The obvious design is the browser one: light up each link in the body and label
it. It was not built, and the reason is
[markdown-rendering-trap](/rendering/markdown-rendering-trap.md) — the body on
screen is tty-markdown's output, which has already rewritten and coloured the
link text. Anchoring a hint to it means pattern-matching a *render artifact*, and
the render is the least stable thing here.

The link list is a value instead: a plain array of resolved targets, which a view
turns into rows and a check asserts on without a terminal. It replaces the body
in the detail pane rather than overlaying it, so the header above stays put and
nothing touches `@detail_scroll` — Esc puts the page back exactly where it was.

# The picker owns the digits

It is a mode, dispatched before the view-switch keys, which is the whole reason
it is a mode and not a pane: while it is open `1` picks a link, and everywhere
else `1` is view one. That ordering is the rule in
[key-routing](/interaction/key-routing.md), and the picker sits innermost — Esc
closes it and leaves a running find still lit, which is
[esc-peels-one-layer](/interaction/esc-peels-one-layer.md) applied to one more
layer.

# The directory link okf will not resolve

`Links.resolve` returns nil for a target ending in `/`, and is right to: a
directory is not a graph edge and the validator has nothing to check about it.
But `[Decisions](decisions/)` is how *every* index.md points at its area, so
reading okf's answer literally left the bundle's front door — the root index,
which §6 makes the way in — as the one page with nothing to follow. Measured, not
guessed: 0 of 5 links resolved there, against 5 of 5 in `interaction/index.md`.

So a nil resolution whose raw target ends in `/` is retried as
`<target>index.md`, and kept only if that path is in `bundle.reserved`. That is a
lookup in a list okf handed over — no directory is walked, no markdown is read,
and a directory with no index stays unfollowable. The judgement: this is
*navigation*, which the TUI owns, not *analysis*, which it must not invent. The
stricter reading is that resolution belongs upstream in okf, and if it lands
there this should collapse into calling it.

# The count it disagrees with

The detail header shows `links →N` from the catalog, and the picker shows its own
count, and **they do not always match**. The header counts graph edges:
concept→concept, deduped, self-links dropped. The picker counts what a reader can
follow, which also includes reserved files and targets nothing has been written
at yet. In the `okf-docs` fixture, `overview` reads 16 against the picker's 17 —
the extra one is a link to `design/index.md`, which the graph has no node for.
Both numbers are right about different questions, so the picker carries its own
label rather than being reconciled to the header.

# The trail came free

`Backspace` pops a stack pushed inside `open_concept` and `open_reserved` — the
two functions every jump already went through. Opening a search hit and following
a concept out of the graph became reversible without either being touched, which
is why the stack lives there rather than in the picker.

# Citations

[1] `lib/okf/tui/model.rb` — `links_for`, `resolve_target`, `describe_link`.
[2] `lib/okf/tui/app.rb` — `handle_follow`, `follow_selected`, `push_trail`, `back`.
[3] `test/integration/links_test.rb` — the area-link case is the one that would
    otherwise have been silently empty.
