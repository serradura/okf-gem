---
okf_version: "0.1"
---

# Hostile Bundle

A conformant OKF bundle whose content is trying to execute script in the page
that renders it. Nothing here is malformed — that is the point. A bundle can
be perfectly valid OKF and still be authored by someone you should not trust,
which is exactly the case the two XSS defenses exist for.

Both paths into the page are represented:

* [Payload](payload.md) - a body full of script, for the sanitizer
* [Attributes](attributes.md) - quotes and a closing script tag in the
  frontmatter, for the inline-data escape
