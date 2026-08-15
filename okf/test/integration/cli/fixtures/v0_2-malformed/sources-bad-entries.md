---
type: Note
title: Sources Bad Entries
description: An entry that is not a mapping, one with no resource, two bad credibility signals, and a prose usage_window override.
sources:
  - https://example.com/bare
  - title: No resource at all
  - resource: https://example.com/signals
    last_modified: mid-May
    usage_count: many
  - resource: https://example.com/windowed
    usage_window: all of June
---

# Overview

`resource` is what makes a source addressable, so its absence is the warning
that matters most here; `last_modified` and `usage_count` are the two
credibility signals with a shape to get wrong.
