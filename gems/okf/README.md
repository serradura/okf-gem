# okf

**The complete Open Knowledge Format toolkit: an agent skill, a CLI and library,
ranked search, and a live knowledge graph. 100% local.**

[Site](https://okfgem.com) · [Docs](https://okfgem.com/docs/) ·
[Live demo](https://demo.okfgem.com) ·
[Project README](https://github.com/serradura/okf#readme)

OKF (Open Knowledge Format) is portable project knowledge: Markdown files with
YAML frontmatter that both humans and agents read from one source. This gem is
the Ruby-native way to work with it — the decisions and the reasoning an agent
cannot re-derive from the code, versioned beside the code they explain.

One install carries the whole workflow: an **Agent Skill** so your agent writes
and curates the knowledge, a **CLI and Ruby library** so it stays correct, and a
**Graph** so anyone can see the shape of what the team knows.

It adds no service to your stack. `rack`, `webrick` and `minifts` are the only
runtime dependencies, there is no native extension and no build step, and it runs
on every Ruby since **2.4** — the one your OS already ships.

## Install

> **In Claude Code**, the plugin is the fastest path: two commands install the whole
> toolchain (skill, `/okf:gem`, and the curation hook). See the
> [project README](https://github.com/serradura/okf#claude-code-plugin).
> Everywhere else, install the gem:

```bash
gem install okf
# or, in a project
bundle add okf
```

Tested and supported on every Ruby from **2.4 through 4.0**. From a checkout,
`bundle exec rake install` builds and installs it locally.

## No Ruby? Use Docker

The official image bundles the CLI, so every `okf` command runs against a bundle
you mount at `/data`:

```bash
docker run --rm -v "$PWD:/data" ghcr.io/serradura/okf validate .
docker run --rm -v "$PWD:/data" -p 8808:8808 ghcr.io/serradura/okf server . --bind 0.0.0.0
```

Tired of the long line? The Docker-backed [`okf` command](https://docker.okfgem.com)
drops the prefix so every verb reads exactly like the native CLI:

```bash
curl -fsSL https://docker.okfgem.com/install.sh | sh   # PowerShell: irm https://docker.okfgem.com/install.ps1 | iex
okf validate .
okf server .
```

Images are published for `linux/amd64` and `linux/arm64` on
[ghcr.io](https://github.com/serradura/okf/pkgs/container/okf).

## Four steps to your first bundle

```bash
okf skill .claude       # 1. teach your agent the format (or: okf skill .agents)
claude                  # 2. start an agent session where your project lives
```

```
/okf migrate <path-to-your-docs>            # 3a. have docs? adopted in place, bodies verbatim
/okf produce based on <path-to-your-code>   # 3b. only code? the skill authors the concepts
```

```bash
okf server <folder>     # 4. explore what you got, as a live graph
```

Then `/okf maintain` keeps it in sync as the code changes.

What the gem does, and which verb does it. This table is the map; **[the
docs](https://okfgem.com/docs/)** are the manual.

| Capability                                                    | What it answers                   | Verb                       |
| ------------------------------------------------------------- | --------------------------------- | -------------------------- |
| [Companion agent skill](https://okfgem.com/docs/skill/)     | Can an agent author it?           | `skill`                    |
| [Conformance validator](https://okfgem.com/docs/cli/validate/)       | Is this a legal OKF bundle?      | `validate`                 |
| [Curation linter](https://okfgem.com/docs/cli/lint/)                | Is it navigable, complete, fresh? | `lint` / `loose`           |
| [Ranked text search](https://okfgem.com/docs/cli/search/)             | Which concept covers X?           | `search`                   |
| [Read views](https://okfgem.com/docs/cli/)                 | What is in here, and where?       | `index` / `dirs` / `catalog` |
| [Interactive graph server](https://okfgem.com/docs/cli/server/) | Can I explore it visually?        | `server`                   |
| [Static render](https://okfgem.com/docs/cli/render/)                  | Can I ship a serverless snapshot? | `render`                   |
| [Library API](https://okfgem.com/docs/library/)               | Can my Ruby program use it?       | in-process                 |

And because knowledge rarely lives in one bundle, a registry gives each one a
name — see [one registry, many bundles](#one-registry-many-bundles) below.

## The graph

One page, from a phone to a desktop: the navigation rail becomes a drawer, the
toolbar folds into a `⚙` sheet, and a tap opens a preview card at the bottom edge
rather than a panel over the whole viewport, so the graph stays live while you
read. Drag the card up for the neighbourhood, tap a link and it walks there in
place.

It is keyboard-first: **`⌘/Ctrl-K`** opens a command palette that searches
concepts, jumps to a view, and — behind a [hub](#one-registry-many-bundles) —
switches bundles. **`/`** jumps to the current view's search, **`?`** answers with
every shortcut. Cluster mode boxes the graph by directory and nests as deep as
your tree does.

To skip the server entirely, **`okf render <dir>`** writes that same page as one
self-contained HTML file, the whole bundle baked in, so you can publish the graph
on GitHub Pages or any static host.

## The command line

Written to be read by an **agent first and a person second** — that is what the
skill drives, with no wrapper in between. Every read verb takes `--json`, the
list views project down to the fields you ask for (`--fields`/`--except`), and
the exit codes are stable enough to branch on in CI.

```bash
okf validate  <dir|@slug>                        # is this legal OKF?
okf lint      <dir|@slug> [--fail-on warn]       # is it navigable, complete, fresh?
okf loose     <dir|@slug>                        # concepts with no links in or out
okf search    <dir|@slug…|@all> <term…>          # ranked retrieval; @all spans every bundle
okf index     <dir|@slug> [--dir D] [--depth N]  # the §8 map: index bodies, rollups, listings
okf dirs      <dir|@slug> [--dir D] [--depth N]  # the shape: every directory and what it holds
okf catalog | files | tags | types | stats  <dir|@slug>   # the browser views, on the CLI
okf references <dir|@slug>                       # the references/ inventory: files, citers, dangling pointers
okf graph     <dir|@slug> [--hubs] [--traffic]   # the raw graph; --hubs ranks concepts, --traffic dirs
okf server    [DIR|@slug…] [-p PORT] [--bind ADDR]   # the live graph: one bundle, or all of them
okf render    <dir|@slug> [-o FILE]              # the same page as one static, self-contained file
okf registry  init | list | set | del | default | rename | group | ungroup   # name & group your bundles
okf registry  link | unlink   <name> <file>      # fold another registry file's bundles in
okf skill     <dest>                             # install the companion agent skill
okf --version
```

Exit codes: `0` success, `1` non-conformant bundle (or a `lint --fail-on`
threshold crossed), `2` usage error. Every flag is in `okf <verb> --help` and in
[the docs](https://okfgem.com/docs/).

```bash
$ okf validate docs
OKF v0.2 conformance — docs
  concepts: 37   index.md: 10   log.md: 1
  ! warn  features/link-suggestions.md: cross-link target not found: `/graph-view.md` (tolerated under §6.1)
  …
  ✓ conformant (33 warning(s))

$ okf server docs
serving 37 concepts at http://127.0.0.1:8808 (Ctrl-C to stop)

$ okf render docs > public/index.html   # the same page, static — host it anywhere
```

## One registry, many bundles

The registry is a per-user, ordered list of bundles in one plain JSON file (`$OKF_HOME/registry.json`, default `~/.okf`) — hand-editable,
greppable, no database. It stores references, never content: the bundles stay in
the repos that own them.

```bash
okf registry set ./docs --as handbook   # give the bundle a name
okf lint @handbook                      # @slug works wherever a <dir> does, from anywhere
okf search @all rate limit              # ranked retrieval across every registered bundle
okf server                              # no args: the whole registry behind one hub
```

Related bundles can share a name: `okf registry group backend @handbook @runbooks`
makes `@backend` stand for the set (members can be groups too, so they nest), and
`okf search @backend rate limit` or `okf server @backend` then targets all of them
at once — a durable subset for the two verbs that take several bundles.

The registry lives under `$OKF_HOME` (default `~/.okf`) — one per user. For one
scoped to a single project instead, `okf registry init` drops a
`.okf-registry.json` in the current directory; okf then discovers it by walking up
from wherever you run, and every registry op — and every `@slug` — resolves through
it in place of the global one. So a bare `okf server` inside that repo serves *its*
bundles with no `$OKF_HOME` setup. The nearest registry wins; `-g` on any
`registry` subcommand reaches the global one for a single command (`okf registry
list -g`, `okf registry set ./docs -g`), and `OKF_NO_DISCOVERY=1` does it for a
whole shell.

Commit that file and it travels with the repo: a bundle under the project root is
stored relative to the registry, so a checkout on another machine — or a container
that mounts the repo — resolves the same bundles unchanged. (Bundles outside the
tree keep absolute paths, which do not travel.)

A repository that already curates its own bundles can lend that list rather than
have it copied. `okf registry link onm ~/ONM/.okf-registry.json` points the global
registry at another registry file: its bundles resolve under their own slugs,
`@onm` names the set, and nothing is duplicated — edit the other file and the
change shows on the next read. They are read-only from here, since the file that
owns them is elsewhere.

```bash
okf registry link okf ~/code/okf/.okf-registry.json   # that repo's own curation, composed
okf search @all rate limit                            # now spans both files
```

Behind the hub each bundle mounts at `/b/<slug>/`, `/b/` lists them all, and the
`⌘/Ctrl-K` palette both switches bundles and **searches every one at once** — type
a few words and the matching concepts appear with their bundle and a snippet, from
wherever you are.

The ⚙ rail opens **Bundles**, the registry on the graph page itself: make
default, rename, remove, where you are already reading. Those controls are the one
thing that does not follow you onto a network — bind anywhere but loopback and
they are refused outright, since `--bind 0.0.0.0` is how a personal tool becomes a
public one.

## Reading a big bundle a level at a time

A few hundred concepts is a map nobody reads whole, so `index` and `dirs` descend
instead of dumping. `--dir` takes a directory **and everything under it**,
`--depth N` bounds how far below that it goes, and the two compose the way you
actually walk a tree:

```bash
okf dirs  @handbook                       # the shape: every dir, what it holds directly and below
okf index @handbook --depth 1 --no-body   # the top of the map, no prose
okf index @handbook --dir platform/api    # now open one branch — with the chain that places it
```

Naming a `--dir` brings its ancestors along, marked `↑`, so a branch is never
shown adrift of the context that says what it is — the root `index.md`'s prose
first among it.

For an agent the saving is the whole point. On a 400-concept bundle the full
`okf index --json` is 313 KB; the skeleton it orients on is 2.8 KB:

```bash
okf index @handbook --json --depth 1 --except body,listing
```

## The agent skill

The gem carries the [companion OKF agent skill](https://okfgem.com/docs/skill/):
a `SKILL.md` plus reference and template files that teach a coding agent to
author, maintain, and consume OKF bundles and to drive
[the command line](#the-command-line).
Because the skill ships inside the gem, installing the gem already puts the skill
on your machine, and the skill's CLI reference can never drift from the
executable it was released with.

The skill routes a small set of verbs. In Claude Code they run as `/okf:gem
<verb>`; used standalone, the skill infers the verb from your request.

| Verb             | What it does                                                                                                |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| _(none)_         | Orient on the bundle and recommend the highest-value next move                                              |
| `search`         | Answer a question from the bundle, token-lean: the map, the finder, only the winning bodies                 |
| `produce`        | Create or extend a bundle from code, docs, or knowledge in people's heads                                   |
| `migrate`        | Adopt existing Markdown docs in place: frontmatter and reserved files added, bodies kept verbatim           |
| `maintain`       | Sync the bundle's content with reality after the code or docs change                                        |
| `refine`         | Restructure it for retrieval: evidence-first, cohesion over balance — proposes, never applies               |
| `consume`        | Use the bundle as context for a task, writing back what you learn                                           |
| `curate`         | Structural upkeep as it stands: `validate` + `lint` + `loose`                                               |
| `doctor`         | Install and verify the CLI, then doctor the bundle                                                          |
| `<okf-cli-verb>` | Run any CLI verb (`validate`, `lint`, `search`, `index`, `server`, the read views) and interpret its output |

Three of those look alike and are not, which is the distinction worth learning
first: **`curate`** keeps the bundle *sound* (the structure as it stands),
**`maintain`** keeps it *true* (the code changed, so the content must catch up),
and **`refine`** changes *where knowledge lives* — the folder a concept sits in,
a fact re-explained in three overviews. Reach for `refine` when nothing is wrong
and everything is hard to find. It reads the evidence, then hands you a proposal
— it never rearranges your bundle on its own.

Point it at your agent's config directory and the tree settles in its own
`skills/okf/` folder, so a shared skills directory never gets the files loose:

```bash
okf skill .claude     # Claude Code      -> .claude/skills/okf
okf skill .agents     # agent-agnostic   -> .agents/skills/okf
```

The resolved directory must be empty unless you pass `--force`, so a customized
skill is never clobbered.

## The library

`require "okf"` gives you the whole thing as Ruby objects — two layers: pure
in-memory data (`OKF::Concept`, `OKF::Bundle`) you build and analyze with no disk
involved, and on-disk handles (`OKF::Concept::File`, `OKF::Bundle::Folder`) that
add load/save/reload/delete.

```ruby
require "okf"

folder = OKF::Bundle::Folder.load("docs")
folder.concepts                  # => [OKF::Concept]
folder.validate                  # => §11 conformance result
folder.lint                      # => curation report
folder.graph                     # => nodes, edges, indexes

require "okf/server/app"
OKF::Server::App.new(folder)     # => a Rack app: the interactive graph, mountable
```

That last line is the point of the Rack app: the graph mounts inside an app you
already have, auth included. The
[Rails guide](https://okfgem.com/docs/guides/rails/) walks it, and the
[library API](https://okfgem.com/docs/library/) covers the pure layer, the
writer, and the lower-level pieces.

## validate and lint are two different questions

`validate` asks *"is this legal OKF?"* and implements the spec's
[§11](lib/okf/skill/reference/SPEC.md#11-conformance) exactly — which means it is *forbidden* to
reject a bundle for a broken link or a missing optional field.

`lint` asks the complementary question, *"is this well-curated, navigable,
trustworthy?"*, over exactly those tolerated things: reachability, backlog,
completeness, freshness, provenance, attestation, migration, hygiene. It is
advisory and exits `0` even with findings unless you pass `--fail-on warn`, or
`--only legacy_timestamp,legacy_citations --fail-on info` to gate a migration
campaign on the two findings that name a bundle's leftover v0.1 spellings and
nothing else.

Keeping them apart is what lets you gate CI on conformance without gating it on
taste. `lint --json` is also the structured input an agent reads to reason about
the two things no checker can compute — contradictions, and *semantic* staleness.

## Trust is data, so you can filter on it

OKF v0.2 lets a bundle say where each concept came from and how far to trust
it — `generated` (who or what wrote it), `verified` (who confirmed it),
`status` (its lifecycle), `stale_after` (a declared expiry) — and this gem
reads the families everywhere: `--status` and `--trust` narrow `catalog`,
`files`, `search`, `tags` and `types`; the graph page shows each concept's
tier beside its type; `lint` reports what expired, against a clock you can
pin (`--today`) for a reproducible report. `okf references` closes the loop
for §10's attested computations, inventorying the `references/` files —
attester code, computation files — that back them, with every pointer that
resolves to nothing named. A v0.1 bundle needs none of this and stays
readable forever (§13); the two Migration findings tell it what to modernize
without ever failing it.

## Extending it

Publish a gem named `okf-*` carrying an `okf/plugin.rb` and installing it is the
whole installation: your verb answers to `okf` and behaves like a built-in.
Nothing an addon registers can displace one, and a broken addon is skipped rather
than taking the CLI down. Three ship alongside this one, with nothing in this
gem naming any of them: [`okf-mcp`](https://rubygems.org/gems/okf-mcp) serves
your bundles over the Model Context Protocol,
[`okf-tui`](https://rubygems.org/gems/okf-tui) browses them full-screen in a
terminal, and [`okf-pro`](https://rubygems.org/gems/okf-pro) writes an
agent's knowledge repository and enforces it at three doors.

The graph page treats a bundle as untrusted content: inlined data is escaped and
every concept body is sanitized before it reaches the DOM, so a script hidden in
Markdown is stripped rather than run. It still loads libraries from a CDN, so
treat an unfamiliar bundle the way you would treat any document from a source you
do not know.

## More

The [project README](https://github.com/serradura/okf#readme) carries the
diagrams, the comparison with `CLAUDE.md`, agent auto-memory and wikis, the
Claude Code plugin, and the way to install the skill into any agent without this
gem (`npx skills add serradura/okf`). The [docs](https://okfgem.com/docs/) are the manual.

And the gem documents *itself* in OKF. `.okf/` ships inside it — a map of what
every file under `lib/` does, and the walk a new verb owes — so from an
installed copy:

```bash
okf server "$(gem contents okf --show-install-dir)/.okf"
```

reads this gem's own knowledge as a graph, in this gem. That is the shortest
honest demonstration there is: the format is good enough that the tool's
maintainers use it on the tool.

## License

Apache-2.0; see `LICENSE.txt`. The Open Knowledge Format specification bundled
with the skill is authored by Google Cloud Platform and included under its own
Apache-2.0 license, Copyright (c) Google LLC. See `NOTICE` and
`lib/okf/skill/reference/APACHE-2.0.txt`.
