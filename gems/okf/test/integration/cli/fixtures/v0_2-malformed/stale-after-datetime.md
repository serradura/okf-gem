---
type: Note
title: Stale After Datetime
description: §5.5 wants a calendar day; this carries a moment.
stale_after: "2026-09-23T10:00:00Z"
---

# Overview

It parses as a date and is still the wrong shape: `stale_after` is an absolute
day, and a value carrying hours means the producer wrote something else. The
precision is the fault, which is why the value parsing is not enough to pass.
