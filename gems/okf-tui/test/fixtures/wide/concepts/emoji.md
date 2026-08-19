---
type: Concept
title: Emoji 🎨 in a Title
description: Pictographs occupy two columns each, and a title carrying them is clipped by column rather than by character.
tags: [emoji, wide]
timestamp: 2026-07-18
---

# Overview

Emoji are two columns wide and one character long: 🎨 🚀 ✅ ⚠️ 📦 🔍.

A row that ends in one of these is where clipping goes wrong first — a clip
computed in characters leaves the row one column too wide, and the frame's right
edge shears on that line only.

# Combining marks

The opposite case: a combining mark adds a character but **no** column. `é`
written as `e` + U+0301 is two characters and one column, so a layout measuring
characters pads it one column short.

| Text | Characters | Columns |
|------|-----------|---------|
| `🎨`  | 1 | 2 |
| `日本` | 2 | 4 |
| `e´`  | 2 | 1 |
