---
type: Note
title: Collision
description: Why a directory named all/ cannot register under the slug all.
tags: [slugs]
---

# Collision

A slug is minted from the directory basename, so `all/` would ask for `all` —
the name `@all` already answers to. The registry treats it as taken and hands
back `all-2`, the same suffix any other collision earns.

An explicit `--as all` is refused instead. The rule underneath is that the gem
may invent a name but never substitute one you chose, so a suffix is right when
the basename was only a guess and wrong when the ask was deliberate.
