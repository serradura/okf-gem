---
type: Component
title: OKF::Bundle::Skeleton
description: The graph reduced to what a reader can hold — directories, the weighted arcs between them, and each link with the cut it survives.
resource: okf/lib/okf/bundle/skeleton.rb
tags: [graph, pure]
timestamp: 2026-07-23T12:00:00Z
---

# Overview

`OKF::Bundle::Skeleton` is the [graph](graph.md) reduced to what a reader can
hold in their head. It is built from a graph's nodes and edges, does no I/O, and
decides nothing about how any of it is drawn — the same purity the graph keeps,
one level of abstraction up. Two consumers read it: [`graph
--traffic`](../capabilities/read-views.md) prints its directory reduction, and
the [graph page](../capabilities/graph-server.md)'s link layer lays a large
bundle out on the backbone it names.

A dense bundle is not dense the way a hub-and-spoke picture is. Measured on a
47-concept bundle with 227 links, the top hub takes 13 inbound and the median 4 —
no 80/20 to exploit, so dropping two-thirds of the *concepts* still leaves 53
edges. The density lives **between directories**: 173 of those 227 links (76%)
cross a directory boundary. That is the reduction worth drawing, and it is why
this class exists at all.

# The two things it produces

- **`dirs` + `arcs`** — the reduction as counts: one row per directory, one
  weighted arc per ordered pair of directories. This is what `graph --traffic`
  prints, with **cohesion** (a directory's internal share of its own traffic)
  derived from them. Directories come off the concept *id* (`OKF.dir_of`), not
  the file path, so this agrees with the graph's own `catalog` and `--dir`
  filter — the side that follows the id, because the edges do.
- **`edges`, each with its `keep_at`** — the smallest cut at which a link
  survives. Nothing prints these; they are what lets the graph page lay a large
  bundle out on its strongest links first, inlined into the page as `EDGE_CUT`
  because the layout needs them before any `fetch()` could answer.

Both are emitted **unthresholded**, and `#suggested_cut` *names* where to cut
rather than cutting — so a caller narrows the picture without this class ever
having to know what a picture is.

# The cut is fitted, not fixed

A fixed arc cut cannot serve both ends of the size range: measured at weight 3
across ten bundles, it left **2 arcs on one and 136 on another** — too tight to
be a picture at one end, no reduction at all at the other. What stays roughly
constant as a bundle grows is not the arc count but the arcs *per box*, since a
node-link diagram reads at about one to two edges per node regardless of size. So
`#suggested_cut` targets 1.5 arcs per directory and reports the weight that
delivers it, floored at 8 for the small end. Cohesion is computed over **every**
arc regardless of the cut, so narrowing the drawn picture never moves the
evidence under it.

# The spine is a sparsifier, not a sample

The `keep_at === 0` set is the **spine**: each concept's single most-connected
neighbour. It is chosen, not sampled, and the property that earns it the name is
that it **touches every linked concept**, so a layout run over it alone strands
nothing and the arrangement is a real one rather than a sketch to be redone.

It is the local-degree sparsifier (Lindner et al.) with a union rule — an edge
survives if *either* endpoint kept it — which is what stops it from stranding the
quiet half of a bundle the way a global "drop the weakest edges" rule does. It is
**not** the disparity filter, the usual name in this territory: that reads an
edge's weight against its endpoint's total, and every link here weighs exactly 1,
which makes every proportion identical and the filter a coin toss. Weighted-graph
tools do not transfer to an unweighted graph just because both are graphs.

# Citations

[1] [okf/lib/okf/bundle/skeleton.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/bundle/skeleton.rb) — the reduction: `dirs`, `arcs`, the fitted `#suggested_cut`, and the `keep_at` sparsifier.
[2] [okf/lib/okf/cli/graph.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/cli/graph.rb) — `graph --traffic`, which prints the directory reduction with cohesion.
