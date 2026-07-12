# AGENTS.md

Maintainer guide for okf-gem — `okf` on RubyGems. The gem reads, validates,
lints, and serves Open Knowledge Format (OKF) v0.1 bundles: directories of
Markdown + YAML frontmatter that humans and agents both read. The bundled skill
(`lib/okf/skill/`) documents the format itself; this file documents how to
change the code without breaking its contracts.

## Map

```
lib/okf/
  path.rb                 pure   path normalization + root-escape guard
  markdown/               pure   format layer: frontmatter (§4), links (§5), citations (§8)
  concept.rb  bundle.rb   pure   the in-memory model (no disk, no stdio)
  bundle/graph.rb         pure   nodes/edges + type/tag indexes
  bundle/validator*.rb    pure   spec §9 conformance (hard errors + soft warnings)
  bundle/linter*.rb       pure   curation-quality report (never rejects)
  concept/file.rb         shell  one-file on-disk handle
  bundle/reader|writer|folder.rb  shell  directory <-> Bundle (writer is atomic, validates before publish)
  server/app.rb           shell  Rack app: / (page), /node, /node/meta, /catalog, /tags, /types
  server/graph.rb + templates/graph.html.erb  the whole UI in one self-contained ERB file
  server/runner.rb        shell  built-in WEBrick <-> Rack bridge (replaces any rackup need)
  skill.rb + skill/       shell  the companion agent skill + its installer
  cli.rb                  shell  the only layer that parses argv, prints, and exits
```

The core/shell split is *enforced*: `test/unit/boundary_test.rb` fails if a pure
file names a shell class or touches `File`/`Dir`/`FileUtils`/stdio. Put new I/O
in the shell; put new logic in the core, pure.

Outside `lib/`, `plugin/` and `.claude-plugin/` are the Claude Code plugin and
its marketplace manifest (the repo doubles as the marketplace): one thin command
that routes to the skill's playbooks (`lib/okf/skill/playbooks/`) or to the
skill itself, a PostToolUse curation hook (`plugin/hooks/scripts/curate.rb`,
plain Ruby on the stdlib, same 2.4 floor), and a generated copy of the skill.
Neither ships in the gem (gemspec reject).

`require "okf"` loads the library only — the model, the analyzers, and the
on-disk handles. The two argv-facing shells, `cli.rb` (and its `optparse`) and
`skill.rb`, load on demand: `exe/okf` requires them, and so must any test that
drives them. An embedding app never pays for the command-line machinery.
`test/unit/loading_test.rb` guards this in a clean subprocess; keep it green when
you touch what `require "okf"` pulls in.

## Hard constraints

1. **Ruby >= 2.4** (rack's own floor — the point is running on the Ruby an OS
   already ships). RuboCop parses at 2.4 and catches syntax, but **not APIs**.
   Do not introduce: `delete_prefix`/`delete_suffix`, `transform_keys`,
   `Dir.children`, `Dir.glob(base:)`, `Struct.new(keyword_init:)`,
   `yield_self` (2.5); `to_h { }`, `then`, `rescue`/`ensure` directly inside a
   `do…end` block, endless string slices `str[i..]`, `YAML.safe_load` keyword
   args outside the Frontmatter shim (2.6); `filter_map`, `tally`, numbered
   block params (2.7); endless methods, hash shorthand (3.x).
   The truth test: `docker run --rm -v "$PWD":/app -w /app ruby:2.4 bash -c
   "bundle install && bundle exec rake test"`.
2. **Runtime dependencies are exactly `rack` and `webrick`.** No ActiveSupport —
   `OKF.blank?` and `Markdown::Frontmatter.stringify_keys` exist precisely so it
   is not needed. A new runtime dependency is a design decision, not a
   convenience; challenge it.
3. **YAML only through `Markdown::Frontmatter`** — `safe_load`, `Date`/`Time`
   permitted, no aliases. The Psych <3.1 positional-argument shim lives there;
   do not call `YAML.safe_load`/`YAML.load` anywhere else.
4. **`validate` and `lint` stay separate.** §9 forbids the validator from
   rejecting broken cross-links or missing optional fields (warnings only);
   lint owns curation findings and never emits conformance errors. New checks go
   to the right side, and exit codes keep the contract: 0 ok, 1 failing bundle,
   2 usage error.
5. **The server page stays self-contained**: one ERB template, inline CSS/JS,
   only Cytoscape, marked, and DOMPurify from a CDN, bodies pulled on demand
   with `fetch()`. No htmx, no bundler, no build step. Two XSS defenses hold the
   line: inlined data goes through `json_for_script` (escapes `<` so it cannot
   break out of its `<script>`), and every fetched body is run through
   `DOMPurify.sanitize(marked.parse(...))` before it reaches `innerHTML`. Keep
   both — a new render path that skips the sanitizer reopens the hole.
6. **The skill ships only from `lib/okf/skill/**`** — that tree is the single
   canonical copy (`okf skill <dest>` installs from it), so edit it there and
   nowhere else. Local installs (e.g. `.agents/`, `.claude/`) are gitignored.
   `plugin/skills/okf` is a *generated* copy for the Claude Code plugin, so
   never edit it there: run `bundle exec rake plugin:sync` after touching the
   skill or bumping the version (the task also stamps
   `plugin/.claude-plugin/plugin.json`), and `test/plugin/sync_test.rb`
   fails on any drift (file lists and SHA-256 checksums). Signature guidance
   lines carry stable markers — `<!-- check:<lint-check-id> -->` when a
   deterministic check enforces the point, `<!-- rule:okf-<slug> -->` for
   pure-judgment craft — as anchors for eval pinning and citation. They render
   invisibly and sync verbatim into the plugin copy, so keep them on the line
   they annotate when you edit it.
7. **Tests use `OKF::TestCase`** (`test/test_helper.rb`): plain Minitest plus
   `test "..."` / block `setup`/`teardown` sugar. The tests run on 2.4 too, so
   the API constraints above apply to `test/` as well.

## Commands

```bash
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
ruby -Ilib exe/okf <cmd> <dir>     # the CLI from the checkout, no install
ruby -Ilib exe/okf server <dir>    # boot the graph server locally
bundle exec rake plugin:sync       # regenerate the plugin's skill copy + version stamp
```

CI (`.github/workflows/main.yml`) runs the default task on every supported Ruby,
2.4 through the current stable. A change is not done until that matrix is green.

## Releasing

1. Bump `lib/okf/version.rb`, then `bundle exec rake plugin:sync` — the plugin
   versions with the gem, so `plugin/.claude-plugin/plugin.json` must follow
   every bump. Move the `Unreleased` notes in `CHANGELOG.md` under the new
   version.
2. `bundle exec rake release` — tags `vX.Y.Z`, pushes commits + tag, pushes the
   gem to RubyGems (MFA required). `release` runs `build`, and `build` aborts
   if the plugin manifest lags the gem version (`rake plugin:verify`), so a
   forgotten sync stops the release instead of shipping.

Gem packaging detail: `spec.files` comes from `git ls-files` minus
`test/`, `bin/`, `.github/`, etc. — a new top-level file ships in the gem unless
the gemspec rejects it, so check `gem build` output when adding one.

## Git

Commits are attributed to the human maintainer only — no AI co-author trailers,
no "generated by" lines, in commits or PRs.

## Working style

- **Think before coding.** State assumptions; if the request is ambiguous, name
  the interpretations instead of picking one silently; push back when a simpler
  approach exists.
- **Simplicity first.** Minimum code that solves the problem — no speculative
  flexibility, no abstractions for single-use code. If 200 lines could be 50,
  rewrite.
- **Surgical changes.** Match the existing style (see `.rubocop.yml` — e.g.
  spaced array brackets `[ 1, 2 ]`, double quotes). Don't improve adjacent
  code; remove only orphans your own change created.
- **Verify against a goal.** Turn every task into a check that can fail: a new
  test, a failing-then-passing repro, the rake default task, the 2.4 Docker
  run. "Works on my Ruby" is not verification here — the floor is.
