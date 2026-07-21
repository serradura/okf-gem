# Design constraints

The enforced boundaries that keep the gem light, portable, and honest. These are
not style preferences — most are checked by a test or CI, and they explain *why*
the code looks the way it does.

* [Browser tests](browser-tests.md) - the graph page is driven in real Chromium, in both render modes, because a string assertion cannot see a collapsed canvas.
* [Core/shell split](core-shell-split.md) - pure logic must never touch disk, stdio, or the shell layer; a test enforces it.
* [Extension points](extension-points.md) - engines, commands and (planned) lint checks all register the same way; `okf/plugin.rb` is the convention, discovery is lazy.
* [Integration first](integration-first.md) - the CLI is the product, so the suite that drives it end to end outranks the unit tests.
* [Ruby 2.4 floor](ruby-floor.md) - runs on the Ruby an OS already ships; newer APIs are banned.
* [Runtime dependencies](runtime-dependencies.md) - exactly `rack`, `webrick` and `minifts`, no ActiveSupport.
* [Search engines are adapters](search-engines.md) - one facade over N engines — the scan by default, the index by capability or by name; a conformance suite, not an oracle.
* [Server trust boundary](server-trust-boundary.md) - the served page sanitizes concept bodies and escapes inlined data; both XSS paths are closed.
