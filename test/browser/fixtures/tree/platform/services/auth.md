---
type: Service
title: Auth
description: Checks the caller; a sibling of the API in the same nested folder.
tags: [core]
timestamp: 2026-06-03T00:00:00Z
---

Auth decides who may proceed. Every allow and every deny is appended to the
[warehouse events](/data/warehouse/events.md).

It lives beside the [API](api.md) under `platform/services/`, so that folder
header carries two files.
