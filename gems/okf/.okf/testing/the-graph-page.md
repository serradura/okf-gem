---
type: Component
title: Testing the Graph Page
description: A string assertion can prove the page was emitted; only a real browser can prove it works — so the browser suite is a local obligation with nothing enforcing it, which is the whole of the arrangement.
tags: [testing, browser, playwright, template]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/render/graph.rb
---

# What the string tests cannot see

The template is ~1,300 lines of inline JS and CSS, and its regressions are the
kind an assertion on the emitted HTML cannot reach: a view that returns with a
canvas Cytoscape measured at 0×0, a filter that stops composing with the search
box, the ≤768px block folding the wrong element, a handler that throws where the
DOM still looks plausible.

`test/integration/render/` proves the page is *emitted* correctly. It cannot
prove the page *works*.

# What does

`test/browser/` — Playwright driving real Chromium, asserting DOM state and
computed CSS at real viewport widths, and failing any test where the page threw.

**Every spec runs twice**, once against `okf server` and once against a `file://`
static `okf render`, because the two modes diverge — fetched endpoints versus
baked `EMBED` — and a pass in one proves nothing about the other.

It is deliberately outside the default `rake` task: it needs node and a ~120MB
Chromium, neither of which belongs on the 2.4 matrix, and the gem takes on no
dependency from it.

# It does not run in CI, and that is the arrangement

It used to, as a non-blocking job, on the argument that a red-but-passing check
made a regression visible without gating a merge on someone else's CDN. That
argument lost on the evidence: the job failed **5 of its last 7 runs** while the
Ruby matrix stayed green, almost all of it jsdelivr rather than the page.

A check that is usually red teaches its readers to ignore it, and a visitor
reads the ✗ as "the gem is broken" rather than "a CDN was slow". Both costs are
real and the signal was not.

So the obligation is unmoved and now unhedged: **a change to the template is not
done until `rake test:browser` is green**, and a bug in the page earns a red spec
there before it earns a patch. Nothing enforces it. Run it and say what it said.

# Before editing the template

Both halves open with a section map, and the JS one also names the three seams
that actually couple the sections — `applyGraphFilter`, `setView`, and the lazy
caches. `grep -n '── '` on the template prints the same list with live line
numbers.

The page's CDN libraries are served from a gitignored `test/browser/vendor/` by
`vendor-cache.js`, a read-through cache keyed on the request URL — so a version
bump is a miss rather than a stale hit. `OKF_NO_VENDOR_CACHE=1` bypasses it,
which is how you check the pins still resolve. It buys robustness, not speed:
28.7s without and 29.0s with, at one worker, because the suite is CPU-bound.

`test/browser/README.md` covers the fixture, the console-error watch, and the
assertion mistakes the suite's first run shook out.
