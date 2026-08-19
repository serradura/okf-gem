# Structure

Every file under `lib/`, grouped by the layer that owns it. One concept owns
each file, and `test/unit/bundle_catalog_test.rb` fails if that stops being true
in either direction — a file no concept names, or a concept naming a file that
is gone.

Fifty files, eight layers, and one rule underneath all of them: **the core is
pure and the shell does the I/O.** `test/unit/boundary_test.rb` fails if a pure
file names a shell class or touches `File`, `Dir`, `FileUtils` or stdio. Put new
logic in the core; put new I/O in the shell.

Read it bottom-up — each layer depends only on the ones below it.

* [The Format Layer](format-layer.md) - `lib/okf.rb`, `path.rb`, `safe_read.rb`, `version.rb`, `markdown/` — pure: paths, containment, frontmatter, links, citations.
* [The Model](the-model.md) - `concept.rb`, `bundle.rb`, `bundle/graph.rb`, `references.rb`, `row_filter.rb`, `skeleton.rb` — pure: a bundle in memory, and every derived view of it.
* [The Analysers](the-analysers.md) - `bundle/validator*.rb`, `bundle/linter*.rb` — pure: §11 conformance, and curation quality, kept deliberately apart.
* [Search](search.md) - `bundle/search.rb` and its two engines — pure: the facade owns the rows, the engines own the matching.
* [The Disk Shell](the-disk-shell.md) - `concept/file.rb`, `bundle/reader.rb`, `writer.rb`, `folder.rb`, `registry.rb` — where directories become bundles and back.
* [The Server and the Page](the-server.md) - `server/app.rb`, `hub.rb`, `hub/not_found.rb`, `runner.rb`, `render/graph.rb` — one ERB template, served or baked.
* [The CLI](the-cli.md) - `cli.rb`, `cli/command.rb`, and the seventeen verb files — the only layer that parses argv, prints, and exits.
* [The Skill](the-skill.md) - `skill.rb` — the companion agent skill and its installer.
