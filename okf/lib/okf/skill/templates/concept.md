---
type: <Concept type, e.g. Service, BigQuery Table, Metric, Playbook, Decision>
title: <Human-readable display name>
description: <Single sentence summarizing the concept.>
resource: <Canonical URI of the underlying asset — omit for abstract concepts>
tags: [<tag>, <tag>]
generated: { by: <actor per §7 — human:<id>, process:<id>, or <producer>/<version>>, at: <ISO 8601, e.g. 2026-06-14T10:00:00Z> }
sources:
  - id: <stable-key-the-body-cites>
    title: <source title>
    resource: <url, bundle-relative path, or scope descriptor>
# Optional §5 families, when they apply:
#   verified: [{ by: <actor>, at: <ISO 8601> }]   — who confirmed the content (a bare mapping reads as a one-element list)
#   status: draft | stable | deprecated            — absent means stable
#   stale_after: YYYY-MM-DD                        — stale on the day itself
---

# Overview

<What this concept is and why it matters. Attribute each empirical claim to a
source by its id: "The events table is sharded daily.[^<stable-key-the-body-cites>]">

# Schema

<Use for assets with fields/columns; otherwise replace with relevant sections.>

| Field | Type | Description |
|-------|------|-------------|
|       |      |             |
