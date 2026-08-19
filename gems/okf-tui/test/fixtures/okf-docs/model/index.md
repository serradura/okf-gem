# The model

The pure, in-memory data structures the gem builds a bundle out of — no disk, no
stdio. Everything else reads or renders these.

* [Concept](concept.md) - one file's worth of knowledge: frontmatter plus body, with a stable id.
* [Bundle](bundle.md) - a collection of concepts you validate, lint, and graph.
* [Graph](graph.md) - concepts as nodes, cross-links as edges, plus type and tag indexes.
