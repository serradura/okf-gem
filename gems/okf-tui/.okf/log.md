# Update Log

## 2026-08-21

* **A linked bundle is read-only, and the four config keys say so before they
  ask** — [registry-write-boundary](decisions/registry-write-boundary.md),
  [which-registry](interaction/which-registry.md). okf's registry can now `link`
  another registry file, whose bundles and groups resolve into the bundles view.
  They list, load, scope and search like any other — but the file that owns them
  is elsewhere, so okf refuses every write. `d`, `n`, `x` and `+` reached okf,
  okf raised, and the message landed on the status line *after* the user had
  typed a new name or confirmed a removal. They now refuse first, naming the
  link; the bundle detail carries `read-only — linked from @onm` and the owning
  file underneath. The registry pane is left alone, because 42 columns cannot
  take another marker without clipping.

* **Nothing was needed to *show* linked bundles at all.** The entries come from
  okf's `listing` and the groups from its `groups_listing`, and okf folds the
  linked half into both rather than into a second method — which is the whole
  point of [which-registry](interaction/which-registry.md)'s rule, arriving from
  the kernel's side this time. `Entry#link` and `Group#link` are read off those
  rows, and an agreement test asserts the field against okf itself, since a
  rename there would leave every refusal above quietly not firing.

## 2026-08-19

* **This bundle moved to OKF v0.2.** `timestamp:` became
  `generated: { by, at }` on all 30 concepts, and the 22 body `# Citations`
  lists became `sources:` — the text preserved, a GitHub URL where the entry
  named a real file, a scope descriptor where it recorded a measurement or a
  repro. Three concepts carried positional `[1]` markers in their bodies; those
  are now `[^1]` footnotes keyed to `sources[].id`, and the sources nothing
  cites lost the id rather than keeping a join half-made.

* **The structure and the catalogue moved into this bundle, and a test holds
  them to the code.** `AGENTS.md` carried a hand-maintained Map of `lib/**` that
  nothing checked, so a file could arrive, move or leave and the Map would keep
  reading plausibly. [Structure](/structure/) now owns it — four concepts over
  ten files — and [Capabilities](/capabilities/) owns the catalogue of the six
  views and the kernel surface behind them, which is the list to read before
  building a seventh. `test/unit/bundle_catalog_test.rb` is the pin, and it
  bites in both directions: a file no concept names, a concept naming a file
  that is gone, or a view catalogue that disagrees with `App::TABS`. The test
  suite's own map moved too, to [the-suite](/testing/the-suite.md), and
  [adding-a-view](/testing/adding-a-view.md) is the walk a new screen owes.

## 2026-08-15

* **Release**: **1.0.0**, the first. Six views over one bundle or many —
  bundles, browse, search, graph, health, help — with the registry and its
  groups as editable configuration, and search across every bundle in scope
  through one shared corpus, so the scores compare between them. It
  [invents no analysis](decisions/invents-no-analysis.md): okf owns the format,
  the model, and every question on screen. The floor is `okf >= 2.0, < 3`, and
  the ceiling is the one exception to
  [no version ceilings](decisions/no-version-ceilings.md) — earned rather than
  conventional, because an okf major is where
  [the silent drift](decisions/okf-capability-drift.md) comes from, and a
  renamed field read as nil is a wrong number with a green suite either side
  of it.
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
