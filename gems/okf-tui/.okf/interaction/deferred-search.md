---
type: Decision
title: Search Submits, It Does Not Follow Typing
description: Enter runs the search rather than every keystroke, because a cross-bundle index is rebuilt per query — and the regression that hides is invisible on screen.
tags: [ux, search, keys]
generated:
  by: human:maintainer
  at: 2026-07-18
sources:
  - title: "`lib/okf/tui/app.rb` — `@searched`, `@search_hits_key`."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/lib/okf/tui/app.rb
  - title: "`test/integration/search_test.rb` — the counting test."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/test/integration/search_test.rb
---

# Overview

Typing in the search field changes nothing. `Enter` runs the search.

Live search was the first design, then a debounce, and both were wrong for the
same reason: a search here builds **one index across every scoped bundle** (see
[cross-bundle-scope](/interaction/cross-bundle-scope.md)), so a search per
keystroke rebuilds that index per keystroke. A debounce only makes the waste
intermittent — it is still doing the expensive thing on a query nobody asked for.

Submitting is also the better interaction: the results stay still while you type,
and the moment of asking is yours rather than a timer's.

# Why it needs a counting test

This is the regression worth guarding, and it is **invisible on a screenshot**.
Pointing the results back at `@query` instead of `@searched` still renders
correctly — the right hits appear, the screen is indistinguishable — it just
rebuilds a full cross-bundle index for every letter. Only a count catches it:

```ruby
searches = 0
app.workspace.define_singleton_method(:search) { |_q| searches += 1; [] }
WORD.each_char { |char| app.handle(char); app.search_hits }
# typing runs 0; Enter runs exactly 1
```

# The cache-key bug underneath

The memoized hits were keyed on the query string itself — which the field
*mutates in place* as you type. The key was the same object as the value's input,
so it always compared equal and the cache never invalidated. The filter had the
identical bug. Both keys are now `.dup`ed.

A cache keyed on a mutable string it does not own is not a cache; it is a
one-shot.
