---
type: Reference
title: Key Routing and Its Modes
description: handle dispatches through modes before the global keys, which is what keeps digits navigating everywhere, and the guard-fallback trap that a Ruby case statement sets for shared letters.
tags: [ux, keys]
generated:
  by: human:maintainer
  at: 2026-07-18
sources:
  - title: "`lib/okf/tui/app.rb` — `handle`, `fallback`, `KEY_VIEWS`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/app.rb
---

# The order

`handle` tries modes in order, innermost first, and only then the global keys:

```
prompt → link picker → find → filter → query field → view switch (1-6) → global keys
```

Each mode returns early, so while one owns the keyboard the layers under it never
see the key.

The link picker is the clearest case of why the order is what it is: it sits
above the view switch so that `1` picks a link while it is open, and means view
one everywhere else — see [following-links](/interaction/following-links.md).

# Nothing grabs the field on arrival

The rule that shapes the whole scheme: **arriving at a view never gives its text
field focus.** Typing starts on `/`, everywhere, in every view that has anything
to look through.

The alternative was tried and is worse. A search view that takes focus on arrival
swallows every printable key, so pressing `3` then `4` types "4" into the query
instead of switching views — the number keys stop being navigation the moment you
land somewhere that can type. Requiring `/` costs one keystroke and buys `1`–`6`
meaning the same thing from everywhere.

In the search view specifically, `Enter` submits and `Esc` releases the field
*without leaving the view*, so the results stay reachable — see
[esc-peels-one-layer](/interaction/esc-peels-one-layer.md) and
[deferred-search](/interaction/deferred-search.md).

What `/` looks through depends on what has focus: a list is filtered, a document
is searched within. When a list filter comes back empty it
[offers the wider search](/interaction/filter-escalates-to-search.md) rather than
stopping there.

# The guard trap

Two letters do different things in different views: `n` is "next match" while
reading and "rename" in the bundles view; `N` is "previous match" and "scope
none".

A Ruby `case` branch matches **whether or not its guard holds** — a `when "n"`
with a failing guard does not fall through to the next branch, it matches and
does nothing. So the shared letters must hand the key back explicitly:

```ruby
when "n" then findable? ? step_match(1) : fallback(key)
when "N" then findable? ? step_match(-1) : fallback(key)
```

Without `fallback`, `n` and `N` were simply swallowed in the bundles view and
rename was unreachable. Any new letter that means two things in two views needs
the same treatment.

Worth knowing that a find now survives until `Esc` rather than until `Enter`, so
the window in which `n` means "next match" is longer than it used to be.

# One key that spans two presses

`q` quits, but only as `q q`. A single press ended the session on one stray
keystroke with nothing to undo it, so the first press arms and says so on the
status line, and the *next key* either confirms or cancels.

The disarm is what makes it correct, and it is placed above the mode handlers on
purpose — typing `q` into a filter or a query has to cancel the arming, or the
chord leaks across a text field and `q` still quits on its own two keystrokes
later. That is the check worth keeping: an arming that never lets go renders
identically to the fixed behaviour until the pair is pressed apart.

`Ctrl-c` stays single. An escape hatch that needs confirming is not one.
