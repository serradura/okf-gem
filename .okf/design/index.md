# Design constraints

The enforced boundaries that keep the gem light, portable, and honest. These are
not style preferences — most are checked by a test or CI, and they explain *why*
the code looks the way it does.

* [Core/shell split](core-shell-split.md) - pure logic must never touch disk, stdio, or the shell layer; a test enforces it.
* [Ruby 2.4 floor](ruby-floor.md) - runs on the Ruby an OS already ships; newer APIs are banned.
* [Runtime dependencies](runtime-dependencies.md) - exactly `rack` and `webrick`, no ActiveSupport.
* [Server trust boundary](server-trust-boundary.md) - the served page sanitizes concept bodies and escapes inlined data; both XSS paths are closed.
