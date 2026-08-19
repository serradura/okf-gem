# Testing

How this gem is tested, and what a change owes before it lands. The root
`AGENTS.md`'s rule applies here as written — a change starts with a failing
test, red for the reason you predicted, then the code, then the same test green
and unedited — and what follows is that rule's shape for this gem's surfaces.

* [The layers](layers.md) - What each layer of the suite proves, and the claims it deliberately does not spend a process on.
* [Adding a tool](adding-a-tool.md) - The walk a new tool owes: where the code goes, which files gain a test, and what the pins will refuse.
