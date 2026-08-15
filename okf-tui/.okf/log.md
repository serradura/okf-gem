# Update Log

## 2026-08-15

* **Note**: **the gem ships no executable.** `okf tui` is the entry point,
  registered through [the plugin seam](decisions/one-door-the-plugin-seam.md),
  so installing the gem is the whole installation. A second binary that only
  aliased the verb would be one more name to install, document and keep
  working, and two front ends are two argument grammars that drift while each
  passes its own tests. What ships instead is one adapter carrying argv and the
  streams and nothing else, which `plugin_test.rb` pins by running the same
  invocation both ways and comparing the message.
* **Note**: **the Rakefile sets its tag prefix behind a guard.**
  `Bundler::GemHelper#tag_prefix=` arrived in Bundler 2.2, and the Bundler that
  Ruby 2.4 ships is 1.17.3 — so setting it unconditionally raises
  `NoMethodError` at Rakefile load on the floor, taking `rake test` down before
  a single test runs. The [2.4 container](decisions/ruby-floor.md) is what sees
  that and CI is not: `ruby/setup-ruby` installs a newer Bundler than the Ruby
  ships. The negative branch *refuses to release* rather than installing the
  tasks unprefixed — an old Ruby is one to test on, never one to release from,
  and a bare `vX.Y.Z` tag here fires the Docker build for the okf image.
* **Creation**: the bundle seeded with 22 concepts across four areas —
  [decisions](decisions/), [interaction](interaction/),
  [rendering](rendering/) and [testing](testing/) — deliberately restating
  neither the `README` (what the views answer, which keys drive them) nor
  `AGENTS.md` (the contracts a change must keep).
