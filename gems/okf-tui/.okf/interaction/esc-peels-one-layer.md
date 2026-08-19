---
type: Decision
title: Esc Peels One Layer
description: Esc ends the innermost active thing and nothing else — the rule that stops it from resetting a list cursor and losing the file the reader had open.
tags: [ux, keys, scar-tissue]
timestamp: 2026-07-18
---

# The rule

`Esc` ends the **innermost** thing currently active, and only that. Press it
again for the next layer out. It is the mirror of
[the mode dispatch](/interaction/key-routing.md): the same layers, unwound one at
a time.

```
link picker → find → filter / facet → (nothing; it never leaves the view)
```

It never switches views. That was an explicit correction during design: pressing
Esc twice in the search view used to jump back to tab 1, which threw away the
results just as the reader was deciding what to do with them. Stopping the search
and moving on are two different intentions, and only one of them was being
offered.

# The bug that made the rule explicit

A find is a layer even after `Enter`. Submitting a find only releases the *field*
— the term stays lit and `n`/`N` still step through the matches — so the find is
still active while `@finding` is false.

Esc from that state fell through to the list's own Esc, which clears the filter
and calls `reset_cursor`. The reader was reading a concept and landed back on the
**first file in the bundle**, having lost the one they had open.[1]

```ruby
if findable? && !@find.empty?
  clear_find
  return
end
```

The file being read is the one thing a find must never cost.

# What stayed the same

The fix is narrow on purpose — a second Esc still clears the filter and resets
the cursor, and these were each verified unchanged:

| Esc pressed | Behaviour |
|---|---|
| after a submitted find | clears the find, cursor untouched |
| again, find gone | clears the filter, resets cursor |
| with no find at all | clears the filter, resets cursor |
| on a graph facet | clears the facet |
| on the help page find | clears the find, stays on help |
| in the link picker | closes it, body and find both untouched |

The picker row is the rule's newest test, and the one that would have repeated
the bug above: it is handled *inside* the picker's own key handler rather than in
`handle_escape`, so closing it can never fall through to the layers beneath —
which is exactly what the find failed to do. See
[following-links](/interaction/following-links.md).

# Citations

[1] Reproduced 2026-07-18 in `test/integration/browse_test.rb`: with `overview`
    open the cursor moved 4 → 1 on Esc. The test was written red first and
    passed unedited after the fix.
[2] `lib/okf/tui/app.rb` — `handle_escape`.
