# Design

How the ecosystem is put together, and the rules that keep it that way. These
are not choices with a date on them — those are [decisions](../decisions/) —
they are the structure everything else is arranged against.

* [Extension points](extension-points.md) - The two registries a sibling arrives through, and the threat model for loading someone else's code.
* [Where knowledge lives](where-knowledge-lives.md) - README, AGENTS.md and `.okf/` answer three different questions, and the same fact may only be in one of them.
* [A rule nothing runs](nothing-runs-it.md) - Every convention here is either executed by something or is a wish, and the difference has been got wrong in writing.
* [The READMEs](the-readmes.md) - Who gets one, why the root's is a menu and a gem's is a manual, and the four rules that outrank taste because each has already gone wrong.
* [The shape of a pull request](pull-requests.md) - The lead-sections-Verification skeleton every PR shares, and the fixed title and body a version bump adds on top.
* [How a change is proven](how-a-change-is-proven.md) - The four obligations that hold in every gem: the test comes first and is read failing, assertions must be able to fail, structure is pinned, the bundle ships with the code.
