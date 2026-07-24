# The model

The pure, in-memory data structures the gem builds a bundle out of — no disk, no
stdio. Everything else reads or renders these.

* [Concept](concept.md) - one file's worth of knowledge: frontmatter plus body, with a stable id.
* [Bundle](bundle.md) - a collection of concepts you validate, lint, and graph.
* [Graph](graph.md) - concepts as nodes, cross-links as edges, plus type and tag indexes.
* [Skeleton](skeleton.md) - the graph reduced: directories, the weighted arcs between them, and each link with the cut it survives.
