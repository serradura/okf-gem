# Testing

How this gem is proven, and what each layer can and cannot catch. The rule that
outranks the rest: **integration first** — a unit test proves a method behaves,
an integration test proves the *product* behaves, and when the two compete for
effort integration wins.

* [The Layers](layers.md) - What each suite proves, how coverage is read, and the three shapes that hide from an integration run.
* [Adding a Verb](adding-a-verb.md) - The walk a new command or subcommand owes, in order.
* [The Graph Page](the-graph-page.md) - Why a string assertion cannot prove the page works, and the local obligation that replaced a CI job.
