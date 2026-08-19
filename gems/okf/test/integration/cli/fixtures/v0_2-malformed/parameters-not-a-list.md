---
type: Attested Computation
title: Parameters Not A List
description: §10.2 defines parameters as a list of typed, named holes.
runtime: bigquery
computation: references/computations/nothing.sql
parameters: year, currency
---

# Overview

A comma-separated string where a list belongs. An agent filling parameters from
this would find none, so the shape is worth a warning even though the concept
reads fine otherwise.
