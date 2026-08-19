---
type: Playbook
title: Adding a View, a Key, or a Panel
description: The steps a new screen owes, in order — where the builder goes, which tables it joins, what the frame test must assert, and the catalogue entry the pin will demand.
tags: [testing, playbook, views]
timestamp: 2026-08-19
---

# Before you add a view, try not to

Six is the whole tab bar, and a seventh is a real cost on every screen. One view
has already been withdrawn for not earning its tab: the `index` map, because
browse answered the same question with a key the reader already had. Check
[the catalogue](/capabilities/views.md) first.

The same instinct applies one level down: a new *number* on an existing screen
usually belongs in okf, not here — [invents-no-analysis](/decisions/invents-no-analysis.md).

# The walk

1. **Write the failing test first**, in `test/integration/`, headless. It renders
   a frame and asserts what is in it. Run it: it must fail for the reason you
   predicted. And prove the assertion can fail at all — a frame test that passes
   against the *old* code is asserting nothing. See
   [headless-frames](/testing/headless-frames.md).
2. **Build rows, not output.** The builder goes in `views.rb` and returns an
   array of strings; it may not touch the terminal. Anything that measures or
   cuts a string goes through `ui.rb`, never `String#length` —
   [ansi-aware-width](/rendering/ansi-aware-width.md).
3. **Join the tables in `app.rb`.** `TABS` (order matters — `help` stays last)
   and `KEY_VIEWS`. Then decide the two behaviours: is it a
   `SINGLE_BUNDLE_VIEW` (follows the active bundle) or scope-wide? Is it a
   `CONTENT_VIEW` (a scrolling page) or a list? Is it a `FILTERABLE_VIEW`?
4. **Ask the reader, don't compute.** `Model` is memoized and already answers
   most of it — [the-workspace](/structure/the-workspace.md) has the table. If
   the answer isn't there, the question is probably okf's.
5. **A destructive action gets a `Prompt`.** Every registry write asks first,
   and the write itself goes through `Workspace` and nowhere else —
   [registry-write-boundary](/decisions/registry-write-boundary.md).
6. **Esc must peel exactly one layer.** A new mode adds a layer to that stack;
   [esc-peels-one-layer](/interaction/esc-peels-one-layer.md) is the rule it has
   to obey.
7. **Update the catalogue** — [capabilities/views](/capabilities/views.md). This
   is not etiquette: `test/unit/bundle_catalog_test.rb` compares that table
   against `App::TABS`, so the suite is red until you do. A new file under
   `lib/` needs its line in [structure/](/structure/) for the same reason.
8. **Run the same test unedited**, then the geometry suite — it runs twice, at
   two widths, and that is where a row that fits in ASCII and overflows in colour
   shows up.

# What the suite structurally cannot catch

One pty test proves the binary boots and nothing else ([pty-test](/testing/pty-test.md)),
and a local run cannot see the dependency resolution that only the matrix
exercises ([ci-matrix](/testing/ci-matrix.md)). Neither is a gap to fill with
more headless tests; they are different questions.
