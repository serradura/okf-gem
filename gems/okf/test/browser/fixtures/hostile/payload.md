---
type: Payload
title: Payload
description: A concept body carrying every script vector the renderer has to strip.
tags: [xss]
timestamp: 2026-06-10T00:00:00Z
---

Markdown passes raw HTML straight through `marked`, so everything below
reaches the sanitizer as real elements. Each one sets a different flag on
`window`; a test asserts none of them are ever set.

<script>window.__xssInline = true;</script>

<img src="x" onerror="window.__xssImg = true;" alt="broken on purpose">

<svg><script>window.__xssSvg = true;</script></svg>

<iframe src="javascript:window.__xssFrame = true;"></iframe>

<div onclick="window.__xssClick = true;" onmouseover="window.__xssHover = true;">
handler attributes on an ordinary element
</div>

<a href="javascript:window.__xssHref = true;">a javascript: link</a>

<form action="javascript:window.__xssForm = true;"><button>submit</button></form>

Some ordinary prose after it all, so a test can tell "the body rendered and
the script was stripped" apart from "the body failed to render at all" —
the distinction a naive assertion would miss. **SAFE-MARKER-9F3A**
