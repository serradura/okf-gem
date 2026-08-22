# okf-tui

A full-screen terminal UI for [Open Knowledge Format](https://github.com/serradura/okf)
bundles: read one, switch between many, configure the registry, and search
across all of them at once. Built on the [TTY toolkit](https://ttytoolkit.org/components/).

Installing it teaches `okf` a verb. There is no second command to learn and
nothing else to set up:

```bash
gem install okf-tui
okf tui                       # every bundle in your registry
okf tui path/to/bundle ...    # those bundles, ad-hoc — the registry is left alone
okf tui @handbook             # a registered bundle; bare @ is the default
okf tui @backend              # a registry group, fanned out to its members
OKF_HOME=/tmp/scratch okf tui # a different global registry
okf help                      # lists `tui` under "installed extensions:"
```

This gem ships **no executable of its own** — deliberately. A second binary that
only aliased `okf tui` would be one more name to install, document and keep
working, and two front ends is two argument grammars waiting to drift. `okf`
finds this gem because it ships `okf/plugin.rb`, the convention any gem can use
to add a verb — see [extension points](https://github.com/serradura/okf/blob/main/.okf/design/extension-points.md).

The argument shape mirrors `okf server` exactly, because it is the same grammar:
`@slug` names a registered bundle, bare `@` the registry default, `@group` fans out
to its members, and `@all` is refused as `okf search`'s alone. Naming directories
is an ad-hoc look at them and never enrols them in the registry — registering stays
an explicit act, here the `a` key.

## Six views

| View | Answers |
|------|---------|
| **1 bundles** | What can I open, which is active, which is the default — the registry's groups, and all registry config |
| **2 browse**  | What is in the bundle, in reading order — `index.md`, `log.md`, then each directory |
| **3 search**  | Which concept covers X — across *every bundle in scope*, ranked together, in whichever of okf's engines answers it |
| **4 graph**   | What shape is its knowledge — narrow by type, tag or dir, or pick a concept to go read |
| **5 health**  | Is it legal, well curated, and well structured — findings on the left (`validate`, `lint`, hubs), standing on the right (dir cohesion, the arcs between dirs, stats) |
| **6 help**    | The keys |

Browse is where okf's §6 map lands too: `/index` narrows the list to the way in
each directory authored, one row per directory, and opens the authored file.

## Two axes, kept apart

"Which bundle" is really two questions, and they move independently:

- the **active bundle** (`●`) — what browse, graph and health are about. `Enter`
  on a bundle changes it.
- the **scope** (`◉`) — which bundles a search covers. `space` toggles one, `A`
  all, `N` none, and `Enter` on a group makes it exactly that group's bundles.
  `N` is how you start a fresh selection.

So you can read one bundle while searching all of them. Opening a search hit
that lives in a *different* bundle switches the active bundle to it.

The scope is also what the search corpus is built over, and it is built **once** and
held — the first query pays for it, the rest are effectively free. Changing the
scope or reloading drops it, because an index that outlives the set it was built
from gives a wrong answer rather than a slow one.

`e` chooses how the query is asked, because okf's two engines disagree by design
and each is wrong for what the other is right for:

| Mode | Engine | Good for |
|------|--------|----------|
| `fuzzy` | full-text index | ranked results, forgives typos |
| `text` | raw scan (okf's own default) | `$OKF_HOME`, `` `minifts` ``, `7.2.0` — terms the index tokenizer splits apart |
| `regexp` | raw scan | a pattern over the same text |

An unparseable pattern says so rather than quietly returning nothing.

Search runs **one index over every scoped bundle**, which is what makes the
scores comparable between them rather than only within one — the same thing
`okf search @all` does.

## `/` looks through whatever has focus

One key, whichever thing the cursor is in:

- **a list** — filters it. Bundles by slug or path, browse by title, id, type or
  tag, graph by type, tag or concept id.
- **a document** — the concept body, and the health and help pages — finds
  within it and scrolls to the hit, with `n` / `N` stepping through the matches.

Nothing grabs the field on arrival, so `1`–`6` mean the same thing everywhere.
In search, `Enter` submits the query and `Esc` stops editing without leaving the
view.

When a browse filter matches nothing, `Enter` takes the term to the search view
and runs it across every bundle — the filter reads metadata in one bundle, and
search reads bodies across all of them.

## `f` follows a link out of the page

A bundle is a graph, and its markdown links are the edges. `f` lists the ones
leaving the document you are reading — pick with `↑` `↓` and `Enter`, or press
`1`–`9` to go straight there. `Esc` puts the body back where you left it, and
`Backspace` returns you to wherever you jumped from.

It reads as what is at the far end, not as the path it was written with: a
concept by its title, a nested `index.md` by its area, and a link with nothing
behind it as knowledge not written yet. That last one is `lint`'s to report, not
an error to raise.

The reserved files are where this earns its keep — an `index.md` is a list of
links by design (§6) and `log.md` is a list of what changed where, so both become
menus into the bundle. The trail is shared, so opening a search hit or following
a concept out of the graph is undone by the same key.

## The bundle wears its verdict

A bundle is clean, has lint warnings, or is not conformant, and that one
judgement drives its colour everywhere it is named — the header, the footer
badge, its row in the registry, its detail pane. The **health tab carries it
too**, so a problem is visible from any view without opening the tab.

## Registry config

In the bundles view: `d` default, `a` add, `n` rename, `x` remove (asks first),
`r` reload. Each writes the registry file and re-reads from disk, so the screen
shows what the file now says. Removing a bundle never touches the bundle on
disk — the registry is a list of references.

A bundle that arrived through an `okf registry link` is read-only — the registry
that owns it is another file — so those keys say so instead of asking, and the
detail pane names the link and the file to edit.

It edits your *configuration*, never your knowledge: there is no bundle writing
anywhere in this gem. Authoring belongs to `okf` and its companion skill.

**Groups.** A registry group is a named, recursive set of bundles — which is to
say a named search scope. Groups list under their own heading, and `Enter` on one
makes a search cover exactly its bundles: the same set `okf search @backend`
merges into one ranking. The detail pane shows both the members the registry
records and the bundles they resolve to, since for a nested group those differ.

**The view has three panes**, and `Tab` cycles them: the registry's bundles, its
groups, and the detail of whichever of the two has focus. `Esc` steps back out one
pane at a time. Two panes means two selections at once, and that is what makes
editing direct — every key acts on a row you can see:

| Key | Pane | Does |
|-----|------|------|
| `Enter` | groups | make a search cover exactly this group's bundles |
| `+` | bundles | the bundle under this cursor joins the group selected below |
| `-` | members | remove the member under this cursor |
| `n` / `x` | groups | rename or delete the group; okf cascades through every member list |
| `c` | bundles | name the bundles now in scope as a new group |

Anything that can lose configuration asks first and names what it is about to do —
`x`, and `-`, which says when the member you are removing is the last one and the
group goes with it. `+`, `c` and `d` add or reorder, and do not ask.

**Which registry.** The same one every other `okf` verb run from the same
directory resolves: a project-local `.okf.json` when one is on the path
up from here, and `$OKF_HOME` (default `~/.okf`) otherwise. `OKF_NO_DISCOVERY=1`
forces the global one. The header names the file it read, so there is never a
question which is in force. A workspace of directories named on the command line
has no registry, and says so rather than pretending to configure one.

## It invents no analysis

`OKF::Bundle::Reader` and `OKF::Registry` are the only parts that touch disk;
everything on screen is a pure call on the resulting in-memory bundles —
`catalog`, `graph`, `validate`, `lint`, `directories`, `hubs`, `skeleton`,
`Bundle::Search`. The TUI is one more shell over the same core the `okf` CLI and
the graph server already use.

That is a rule with teeth, not a slogan: the dir facet's counts are checked in CI
against `okf dirs --json`, and the cohesion table against `okf graph --traffic`,
row for row. If okf and this disagree about a number, the suite fails.

It keeps okf's contracts visible too: `validate` and `lint` are separate
sections because they answer different questions, reads are best-effort so an
unreadable file is reported (`⊘ n unreadable`) rather than fatal, and a bad
directory exits `2`, the usage-error code.

## Requirements

Ruby >= 2.4 — the same floor as okf, which takes it from rack: the tool should
run on whatever Ruby the OS already ships. `okf >= 2.0` is the other requirement,
and installing this gem pulls it in: every screen here answers with something the
kernel's OKF v0.2 work published, and against an older one each would fail
silently rather than loudly.

## Development

`bin/setup` to install, `bundle exec rake` to run the tests and RuboCop.
`bundle exec okf tui` runs it from the checkout — okf is a bundle dependency, so
the verb resolves the same way it does for a user. See [AGENTS.md](AGENTS.md)
for the contracts a change has to keep.

This gem ships its own knowledge bundle at `.okf/`, and it is the gem's own
documentation rather than a sample: what every file under `lib/` does, what each
of the six views answers, and why the interaction model is what it is. `okf tui
.okf` reads it in this program, which is the shortest honest demo there is.

## License

Apache-2.0.
