# AGENTS.md

Maintainer guide for okf-gem, a monorepo. It ships four gems around one format:
`okf`, the baseline that reads, validates, lints, searches and serves Open
Knowledge Format (OKF) v0.2 bundles — directories of Markdown + YAML frontmatter
that humans and agents both read — and three surfaces over it, an MCP shell, a
terminal UI and an enforcement layer.

**This file owns everything above a single gem**: the layout, the shared
obligations, the distribution surfaces, the conventions for READMEs, pull
requests and releases, and the rules about attribution and working style. It
owns no gem's contract. Each of the four carries its own `AGENTS.md` beside its
code and its own `.okf/` bundle beside that, and this file routes to them rather
than restating them — the argument for the split, and the drift that motivated
it, are [.okf/design/where-knowledge-lives.md](.okf/design/where-knowledge-lives.md).

## Where to go

Read the guide for the gem you are changing; it names the bundle concepts under
it. This file is the general rule, a gem's is the instance.

| working on | read | then |
| --- | --- | --- |
| the baseline gem | [`gems/okf/AGENTS.md`](gems/okf/AGENTS.md) | `okf search @okf <term>` |
| the MCP shell | [`gems/okf-mcp/AGENTS.md`](gems/okf-mcp/AGENTS.md) | `okf search @okf-mcp <term>` |
| the terminal UI | [`gems/okf-tui/AGENTS.md`](gems/okf-tui/AGENTS.md) | `okf search @okf-tui <term>` |
| the enforcement layer | [`gems/okf-pro/AGENTS.md`](gems/okf-pro/AGENTS.md) | `okf search @okf-pro <term>` |
| the plugin, the skills, the resources, or a decision that binds all four | this file, then [`.okf/`](.okf/) | `okf search @okf-eco <term>` |

`okf search @all <term>` reaches every bundle at once, and `rake serve` opens
this repository's own as a graph.

## Map

The repository — a `gems/` container holding one directory per gem, and at the
root only what is not a gem. A directory under `gems/` **is** a gem and is named
for the gem it ships; everything at the root is named for what it is. The
container says where gems live, never which gem this is — the whole argument,
including the rejection it reverses, is in
[.okf/decisions/monorepo-layout.md](.okf/decisions/monorepo-layout.md).

```
gems/okf/       the baseline gem, registered as plain `@okf`. Floor 2.4; deps
                exactly rack + webrick + minifts. Ships the skill, and its own
                `.okf/` inside the gem
gems/okf-mcp/   the MCP shell: the kernel's capabilities as MCP tools + prompts.
                Floor 2.7 — the `mcp` SDK's — deps exactly `mcp` + `okf`
gems/okf-tui/   the terminal UI: six views over one or many bundles, and the
                registry. Floor 2.4, deps `okf` + the TTY toolkit
gems/okf-pro/   the enforcement layer: `okf pro setup` writes an agent's
                knowledge repo, `okf pro hook` runs one gate against one hook
                event. Floor 2.4, deps exactly `okf`. Its `hook` verb is the one
                place in the repo where exit 1 is *non-blocking* and 2 refuses
plugin/         the Claude Code plugin — generated skill copy, command, curation hook
.claude-plugin/ the marketplace manifest (the repo doubles as the marketplace)
skills/         the skills a generic installer reads (`npx skills add serradura/okf-gem`):
                a generated copy of okf's, and okf-principles, whose canonical
                copy this is — it documents a way of structuring instructions,
                not okf's code, so it belongs to no gem
.okf/           the ecosystem's map, registered as `@okf-eco`: a concept per
                gem, per plugin item, per skill and per resource, plus the
                format, the decisions and the design that govern them all. Each
                gem's own knowledge is in its own `.okf/`, beside its code
.okf-registry.json
                every bundle in the tree, addressable as `@slug` — and while you
                stand anywhere under this root it *replaces* your global
                $OKF_HOME registry outright, rather than adding to it
Dockerfile      builds gems/okf/ — from a root context, because the gemspec
                needs .git
Rakefile        a delegator: `rake` runs every gem's default task
```

Each sibling ships **no exe**: `okf mcp`, `okf tui` and `okf pro` arrive through
the kernel's plugin seam, which is
[.okf/decisions/one-door-per-sibling.md](.okf/decisions/one-door-per-sibling.md)
— and the threat model for that seam, which every sibling arrives through, is
[.okf/design/extension-points.md](.okf/design/extension-points.md).

`plugin/`, `.claude-plugin/` and `skills/` are the three distribution surfaces
the repo carries for a tree that lives inside a gem. None of them ships in the
gem, and none may be edited: `plugin/skills/okf` and `skills/okf` are generated
by `rake skill:sync` in the *gem's* Rakefile, and two guards fail the build on
drift. Why the task lives there, why there are two destinations, and what the
curation hook does are
[.okf/skills/okf-skill.md](.okf/skills/okf-skill.md) and
[.okf/plugin/](.okf/plugin/).

The root `Rakefile` runs plain `rake`, not `bundle exec rake`: there is no root
Gemfile, because the gems here do not share a Ruby floor and one lockfile could
never resolve for all of them. It names each gem's `BUNDLE_GEMFILE` explicitly
when it delegates — bundler exports that variable to everything it runs, so a
nested `bundle exec` otherwise inherits the parent's bundle. `bundle exec rake`
at the root fails with "Could not locate Gemfile", and that is the intended
answer rather than an oversight. Root `rake release` refuses too: Bundler reads
the gemspec in its working directory, so a release is cut from the gem's own.

The repo-level Ruby — the root Rakefile and the curation hook — sits outside
every gem, so no gem's `rake rubocop` reaches it. The root `.rubocop.yml`
inherits the baseline gem's and covers exactly those two files.

## What every gem owes

A gem's own floor, dependency limits and contracts are its own file's. These
four hold everywhere, and a reviewer checks them:

- **A change starts with a failing test at the level the change lives at**, run
  and read: it must fail for the reason you predicted, not because a fixture is
  missing. Then the code, then the same test green and **unedited**. A test
  written after the fix certifies only the code it was read off. A bug report
  earns a red test before a patch. Pure refactors are the exception, not a
  licence — say so rather than skipping the step quietly.
- **Assertions must be able to fail for a real reason.** Run the thing, read
  what it actually prints, then assert *that*. Never assert what you assume the
  code does — that is how a green suite certifies a bug.
- **Structural documentation is pinned, not trusted.** Every gem's `.okf/structure/`
  is held to its tree by its own `test/unit/bundle_catalog_test.rb`: a file under
  `lib/` that no concept names, a concept naming a file that is gone, or a
  catalogue out of step with the constant it mirrors is a red suite. The rest of
  a bundle cannot be pinned that way and is not pretended to be — see
  [.okf/design/nothing-runs-it.md](.okf/design/nothing-runs-it.md).
- **The bundle is maintained in the same commit as the code it documents**, not
  as a follow-up chore.

## Commands

From the repo root — plain `rake`, no bundler:

```bash
rake                               # every gem's default task, then the repo-level rubocop
rake test                          # every gem's suite
rake okf                           # validate + lint every registered .okf bundle
rake serve                         # serve this repo's own .okf as a graph
```

Everything about one gem — its suite, its CLI from the checkout, its floor
container — is in that gem's own guide.

CI (`.github/workflows/main.yml`) is **one job per gem**, not a gem axis on one
matrix: the floors diverge, so a shared matrix would be mostly exclusions. Each
job sets `working-directory` on both the job and `ruby/setup-ruby` (the action
needs its own input to find the Gemfile it caches against). Alongside them a
single `lint` job runs the root `rake rubocop` on one modern Ruby — that job is
the only thing standing between `plugin/hooks/scripts/curate.rb` and being
linted by nobody, and before it existed this repo shipped a commit claiming the
root `.rubocop.yml` "restores lint coverage" when in CI it did nothing at all.

A change is not done until both are green.

## The bundles and the log

This repo carries **five** OKF bundles — `.okf/` at the root for the ecosystem,
and one inside each gem. `rake okf` validates and lints all five, reading the
slugs from `.okf-registry.json` rather than a list.

Which bundle: **a gem's own** for anything about that gem — its code, its
capabilities, its design arguments, its tests. **The root's** for what belongs
to no single gem: the format, the four gems as a set, the plugin, the skills,
the resources, and the decisions and design that govern them. The test is
whether the fact survives deleting a gem; if it does, it is the root's. The
three-way split between a README, an `AGENTS.md` and a bundle is
[.okf/design/where-knowledge-lives.md](.okf/design/where-knowledge-lives.md).

A concept cannot link out of its own bundle — `Path.normalize_relative!` refuses
every `..` segment — so a reference across the line names the other bundle in
prose (`` `@okf capabilities/linter` ``). That is a real cost of the split, paid
deliberately: 208 edges crossed the root bundle before it, and every one that
now leaves was rewritten rather than dropped.

`.okf/log.md` is held to one rule that outranks the reflex to write down what
happened: **it records durable knowledge and shipped behavior, not the process
that produced them.** The rule is general OKF craft rather than a fact about this
repository, so it is stated once where it travels — `rule:okf-log-durable-only`
in the skill's
[authoring.md](gems/okf/lib/okf/skill/reference/authoring.md), cited by the
maintain playbook and the Closeout gate. A durable lesson a change taught goes in
the concept it is about, stated as a principle, in the same commit as the code;
the reader finds it there, not by reading history.

## The READMEs

Who gets one, why the root's is a menu and a gem's is a manual, what the site
owns instead, and the four rules that outrank taste — every command runs as
written, every number is measured now, no deprecated spelling, a new verb ships
with its README line — are
[.okf/design/the-readmes.md](.okf/design/the-readmes.md).

## Pull requests

Every PR is a written argument for its own diff: a lead paragraph with no
heading, `##` sections named for what they settle, and `## Verification` last
with the commands actually run and their real numbers. **Argue, don't restate** —
the diff is one tab away. A PR that touches a gem's `version.rb` is a release PR
and adds the `release` label, a fixed title and a fixed body on top. The
skeleton, the three rules that outrank Verification's formatting, and both fixed
shapes are [.okf/design/pull-requests.md](.okf/design/pull-requests.md).

## Releasing

A release is cut **from the gem's own directory**, and the steps are that gem's
guide's. What is shared is the tag convention: **the bare `v*` series belongs to
the baseline gem** and a sibling tags `<gem>/vX.Y.Z`. The asymmetry is
deliberate — the Docker workflow fires on `v*`, and a glob does not match across
`/`, so a sibling's release cannot trigger a build of an image that ships
something else. Prefixing everything would have been tidier and would have ended
a public tag series mid-history to buy nothing.
[.okf/decisions/release-and-tags.md](.okf/decisions/release-and-tags.md).

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
- **Verify against a goal.** Turn every task into a check that can fail, and
  prove it can: break the code on purpose and watch the test report it. A green
  suite that cannot go red is not verification, and "works on my Ruby" is not
  either — the floor is.
