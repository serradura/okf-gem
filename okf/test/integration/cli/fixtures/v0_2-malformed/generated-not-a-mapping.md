---
type: Note
title: Generated Not A Mapping
description: §5.2 defines generated as a { by, at } mapping; this is a scalar.
generated: 2026-05-28T09:15:00Z
---

# Overview

A producer that wrote the timestamp straight into `generated` rather than into
its `at` key. Tolerated on read — the concept simply falls back — and warned
about here.
