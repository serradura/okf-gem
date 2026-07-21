---
type: Service
title: API
description: The public entry point, nested two directories deep.
tags: [edge, core]
timestamp: 2026-06-02T00:00:00Z
---

Every request enters here. Before doing anything else, the API hands the caller
to [auth](auth.md) to be checked.

Its directory, `platform/`, holds nothing but the `services/` folder beneath it
— a directory that is only a parent of other directories.
