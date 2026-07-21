---
type: Attributes
title: 'Attributes </script><script>window.__xssTitle = true;</script>'
description: 'Quotes " and ''apostrophes'' and <angle> brackets & an ampersand.'
tags: ['evil"onmouseover="window.__xssTag = true', xss]
timestamp: 2026-06-11T00:00:00Z
---

This concept attacks the *other* path. Its title, description and tags are
not fetched as a body — they are baked into the page as JSON and later
interpolated into HTML attributes, so they meet two different defenses:

* `json_for_script` (Ruby) escapes `<` when writing the payload, so the
  `</script>` in the title above cannot close the script block it sits in.
* `esc()` (JS) escapes quotes as well as angle brackets, because it feeds
  attributes and not only text. The tag above is the classic breakout: if
  quotes survive, `data-focus-tag="…"` gains a real `onmouseover` handler.

[Back to the payload](payload.md).
