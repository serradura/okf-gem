---
type: Concept
title: A Dead Filter Offers the Wider Search
description: Filtering reads metadata in one bundle and searching reads bodies across all of them, so a filter that matches nothing offers the search rather than leaving a dead end.
tags: [ux, search]
generated:
  by: human:maintainer
  at: 2026-08-13
sources:
  - title: "`lib/okf/tui/views.rb` — `escalation_panel`."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/views.rb
  - title: "`lib/okf/tui/app.rb` — `filter_found_nothing?`, which is where the two views' conditions live side by side."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/lib/okf/tui/app.rb
  - title: "`test/integration/search_test.rb` — \"a filter that matches nothing offers the wider search\"."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/integration/search_test.rb
  - title: "`test/integration/groups_test.rb` — \"a filter matching a group but no bundle has found something\"."
    resource: https://github.com/serradura/okf/blob/main/gems/okf-tui/test/integration/groups_test.rb
---

# Overview

`/` filters the list you are in — bundles by slug or path, browse by title, id,
type or tag, graph by type, tag or concept id. When it matches nothing, the empty
result is not a dead end: `Enter` takes the term to the search view and runs it
across every scoped bundle.

# Why the escalation is honest

The two are not the same search narrowed differently — they read different things
in different places:

| | reads | covers |
|---|---|---|
| filter | metadata (title, id, type, tag) | the current bundle |
| search | bodies, ranked | every bundle in scope |

So "no concept here is *called* that" and "nothing anywhere *says* that" are
genuinely different answers, and a reader who got the first one almost always
wants the second. Making them ask again in another view — retyping the term — is
the whole friction the escalation removes.

It is offered rather than automatic. The jump changes what you are looking at and
runs work, so it stays an accepted suggestion, consistent with
[search submitting rather than following typing](/interaction/deferred-search.md).

# The registry filter escalates too

A filter in the bundles view looks through a dozen slugs and the group names
beside them, which is a narrower thing than it looks: a term matching none of
them is usually a question about what the bundles *say*, not about what one is
called. `Enter` there takes the term to the search view over every bundle, the
same key doing the same thing.

**Both panes have to be empty, not just the focused one.** A filter matching a
group and no bundle has found something, and the first cut of this read only the
bundles pane — so `Enter` escalated on the keystroke that was accepting the
filter, taking the filter, the view and the group the reader was pointing at with
it. "The filter found nothing" is a claim about the whole view.
