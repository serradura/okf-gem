---
type: Constraint
title: The graph page is proven in a real browser
description: A string assertion over rendered HTML cannot see a collapsed canvas or a folded breakpoint, so the page is driven in Chromium — in both render modes, with any thrown error failing the run.
resource: test/browser
tags: [testing, render, server, architecture]
timestamp: 2026-07-20T18:00:00Z
---

# Overview

[`okf render` and `okf server`](../capabilities/render.md) share one ERB
template carrying ~1,300 lines of inline JS and CSS. Its regressions are not
the kind a string assertion catches: a view that returns with a canvas
Cytoscape measured at 0×0, a filter that stops composing with search, a
breakpoint folding the wrong element, a handler that throws while the DOM
still looks plausible. `test/integration/render/` proves the page is
*emitted* correctly and cannot prove it *works*.

`test/browser/` closes that gap with Playwright: real Chromium, DOM state and
computed CSS at real viewport widths. It is the same argument
[integration-first](integration-first.md) makes for the CLI, applied to the
one surface the CLI cannot reach.

# Every spec runs in both render modes

The template has two data paths that diverge in a load-bearing way: served
live it fetches `/node`, `/catalog`, `/index` and `/log` on demand; rendered
statically it reads the same payloads out of a baked `EMBED` constant. A pass
in one proves nothing about the other, so the suite defines two Playwright
projects and runs every spec twice — one against a booted `okf server`, one
against a `file://` static render generated fresh each run.

Where the modes honestly differ the spec says so and asserts both answers.
Full-text search is the worked example: bodies enter the index only when they
are present, and they are present only in a static bake, so the same query
finds a concept in one mode and not the other. Pinning a single expectation
would certify a lie in whichever mode it did not describe.
<!-- rule:okf-both-render-modes -->

# A thrown error fails the run

The shared fixture watches `pageerror` and console errors and fails the test
even when every assertion passed. This is the check no per-behavior test
provides: a handler that throws leaves a plausible-looking DOM that
assertions walk straight past, and "I changed the filter and the catalog
quietly stopped rendering" is exactly the failure this file keeps producing.
It is also the only thing giving the suite reach into surfaces it does not
otherwise test.

# Outside the default task, and non-blocking in CI

It needs node and a ~120MB Chromium, neither of which belongs on the
[Ruby 2.4 floor](ruby-floor.md) matrix, and the gem takes on no
[runtime dependency](runtime-dependencies.md) from it. So it is opt-in locally
(`rake test:browser`) and runs in CI as a separate job marked
`continue-on-error`.

Non-blocking is a judgement about *what the signal is worth*, not a hedge. The
page loads Cytoscape, marked and DOMPurify from a CDN at boot — a dependency
the [trust boundary](server-trust-boundary.md) already names — so a red job can
mean a regression or can mean jsdelivr was slow, and a check that cries wolf on
someone else's PR gets muted within a month. The job stays visibly red and
uploads its traces; the run passes anyway.

Which leaves the obligation where it was: a change to the template is not done
until the suite is green locally. An automated gate nobody trusts is weaker
than a rule the maintainer keeps.
<!-- rule:okf-browser-suite-before-merge -->

# Coverage is measured against the page's own history

The suite's worth is measured the same way
[integration coverage](integration-first.md) is — as a map, not a score, and
against the honest denominator. Reading all 44 commits behind the template
yields ~230 behavioral contracts, ~94 of them fixes for bugs that actually
shipped. A regression fix is the sharpest test target there is: a failure mode
already proven reachable in this file.

The suite covers 10 of those 94. It is strong on the interaction spine and on
both XSS defenses; it is absent on the periphery — the Files view alone
accounts for 28 of the 94 and is touched by two assertions.
`test/browser/COVERAGE.md` carries the ranked gap list. Its top entry used to
be body sanitization, which no suite checked at all; that one is now closed
and mutation-verified, and the [trust boundary](server-trust-boundary.md)
carries the table.

# Writing a spec: read the page, then assert

Assertions must be able to fail for a real reason, which here means two things
beyond the [test-first rule](integration-first.md).

**Read what the page renders, not what the code looks like it renders.** Four
of the first green run's assertions were wrong this way — panel labels are
sentence-case in markup and uppercased by `text-transform`; the Index rail
item opens a file rather than pressing the filter beside it.

**Assert the thing that can actually collapse.** The suite's first
canvas-resize test read `cy.width()`, which reports the live container and
stays correct while the render is collapsed — it passed with every resize path
deleted. A test that cannot fail is worse than no test, because it is counted.
Mutation-check a new spec by breaking the code it covers and confirming it
goes red for the predicted reason.
<!-- rule:okf-assert-the-collapsible -->

# Citations

[1] [test/browser/README.md](https://github.com/serradura/okf-gem/blob/main/test/browser/README.md) — the two projects, the fixture, the console watch, the assertion mistakes the first run shook out.
[2] [test/browser/COVERAGE.md](https://github.com/serradura/okf-gem/blob/main/test/browser/COVERAGE.md) — the history-derived catalog and the ranked gap list.
