---
type: Note
title: Verified Not A List
description: §5.2 allows a list or a single bare mapping — not a scalar.
verified: yes, by me
---

# Overview

A bare mapping is legal and must be read as a one-element list. A scalar is
neither, so it reads as no verification at all and warns.
