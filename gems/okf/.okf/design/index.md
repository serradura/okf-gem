# Design constraints

The boundaries that keep this gem light and honest. Each is enforced by
something — a test, a build task, a CI job — rather than intended.

The two that are *not* this gem's live in the repository bundle: the extension
seam every sibling arrives through (`@okf-eco design/extension-points`) and the
monorepo layout (`@okf-eco decisions/monorepo-layout`).

* [The core/shell split](core-shell-split.md) - Pure logic and I/O are separated, and a test fails the build when they are not.
* [Integration tests are the critical layer](integration-first.md) - The CLI is the product, so the suite that drives it end to end outranks the unit tests.
* [The graph page is proven in a real browser](browser-tests.md) - A string assertion cannot see a collapsed canvas, so Chromium drives the page in both render modes.
* [Ruby 2.4](ruby-floor.md) - The floor is rack's own, and the point is running on the Ruby an OS already ships.
* [Runtime dependencies](runtime-dependencies.md) - Exactly three, and a fourth needs an argument as strong as the third's.
* [Search engines](search-engines.md) - One facade, two engines, chosen by what the query needs rather than by name.
* [The server trust boundary](server-trust-boundary.md) - What the server will answer for, and what it refuses regardless of flags.
* [What ships, and the two ways it has gone wrong](packaging.md) - `spec.files` is subtractive, `.dockerignore` implies the reject list one way only, and a symlink installs dangling on the old half of the matrix.
