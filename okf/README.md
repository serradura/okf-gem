# okf

**The complete Open Knowledge Format toolkit: an agent skill, a CLI and library,
ranked search, and a live knowledge graph. 100% local.**

[Site](https://okfgem.com) · [Docs](https://okfgem.com/docs/) ·
[Live demo](https://demo.okfgem.com) ·
[Project README](https://github.com/serradura/okf-gem#readme)

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

```bash
gem install okf
# or, in a project
bundle add okf
```

No Ruby? The official image carries the CLI:

```bash
docker run --rm -v "$PWD:/data" ghcr.io/serradura/okf validate .
```

The Docker-backed [`okf` command](https://docker.okfgem.com) drops the prefix so
every verb reads exactly like the native CLI.

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
okf index     <dir|@slug> [--dir D] [--depth N]  # the §6 map: index bodies, rollups, listings
okf dirs      <dir|@slug> [--dir D] [--depth N]  # the shape: every directory and what it holds
okf catalog | files | tags | types | stats  <dir|@slug>   # the browser views, on the CLI
okf graph     <dir|@slug> [--hubs] [--traffic]   # the raw graph; --hubs ranks concepts, --traffic dirs
okf server    [DIR|@slug…] [-p PORT] [--bind ADDR]   # the live graph: one bundle, or all of them
okf render    <dir|@slug> [-o FILE]              # the same page as one static, self-contained file
okf registry  init | list | set | del | default | rename | group | ungroup   # name & group your bundles
okf skill     <dest>                             # install the companion agent skill
okf --version
```

Exit codes: `0` success, `1` non-conformant bundle (or a `lint --fail-on`
threshold crossed), `2` usage error. Every flag is in `okf <verb> --help` and in
[the docs](https://okfgem.com/docs/).

**A registry names your bundles.** `okf registry set ./docs --as handbook` once,
then `@handbook` works anywhere a `<dir>` does, from any directory; `okf search
@all rate limit` spans every one of them, and a bare `okf server` hosts them all
behind one hub. `okf registry init` scopes one to a single project instead, and a
committed `.okf-registry.json` travels with the repo.

**A big bundle is read a level at a time.** `okf index --depth 1 --except
body,listing` is the map an agent orients on — on a 400-concept bundle, 2.8 KB
against the full 313 KB — and `--dir` then opens one branch, bringing the
ancestors that say what it is.

## The library

`require "okf"` gives you the whole thing as Ruby objects — two layers: pure
in-memory data (`OKF::Concept`, `OKF::Bundle`) you build and analyze with no disk
involved, and on-disk handles (`OKF::Concept::File`, `OKF::Bundle::Folder`) that
add load/save/reload/delete.

```ruby
require "okf"

folder = OKF::Bundle::Folder.load("docs")
folder.concepts                  # => [OKF::Concept]
folder.validate                  # => §9 conformance result
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
[§9](lib/okf/skill/reference/SPEC.md#9-conformance) exactly — which means it is *forbidden* to
reject a bundle for a broken link or a missing optional field.

`lint` asks the complementary question, *"is this well-curated, navigable,
trustworthy?"*, over exactly those tolerated things: reachability, backlog,
completeness, freshness, provenance, hygiene. It is advisory and exits `0` even
with findings unless you pass `--fail-on warn`.

Keeping them apart is what lets you gate CI on conformance without gating it on
taste. `lint --json` is also the structured input an agent reads to reason about
the two things no checker can compute — contradictions, and *semantic* staleness.

## Extending it

Publish a gem named `okf-*` carrying an `okf/plugin.rb` and installing it is the
whole installation: your verb answers to `okf` and behaves like a built-in.
Nothing an addon registers can displace one, and a broken addon is skipped rather
than taking the CLI down.

The graph page treats a bundle as untrusted content: inlined data is escaped and
every concept body is sanitized before it reaches the DOM, so a script hidden in
Markdown is stripped rather than run. It still loads libraries from a CDN, so
treat an unfamiliar bundle the way you would treat any document from a source you
do not know.

## More

The [project README](https://github.com/serradura/okf-gem#readme) carries the
diagrams, the comparison with `CLAUDE.md`, agent auto-memory and wikis, and the
Claude Code plugin. The [docs](https://okfgem.com/docs/) are the manual. And the
repo documents *itself* in OKF — clone it and run `okf server .okf` to read this
gem's own knowledge as a graph.

## License

Apache-2.0; see `LICENSE.txt`. The Open Knowledge Format specification bundled
with the skill is authored by Google Cloud Platform and included under its own
Apache-2.0 license, Copyright (c) Google LLC. See `NOTICE` and
`lib/okf/skill/reference/APACHE-2.0.txt`.
