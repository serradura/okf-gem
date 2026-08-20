# Orienting — `index` and `dirs`

Kind: reference. Answers: which view to run first on a bundle you do not know,
how `--dir`, `--depth` and the ancestor chain compose, what a synthesized
listing means, and how to keep the map from paging the whole bundle.

The shared contract — `@slug` refs, exit codes, `--json`, the filters — is in
[cli.md](../cli.md) and is not repeated here.

## index — the progressive-disclosure map (§8)

The "orient before you read" view, and the read verb that sees the layer the
concept views can't: `index.md` files are reserved/structural, so
`catalog`/`files`/… never show them (in the browser, the Indexes tab and
folder clicks render this same map). `okf index <dir>` prints one entry per directory
that holds concepts or carries an `index.md`, root first — the authored index body
(frontmatter stripped), a `type`/`tag` rollup over the concepts that live directly
there, its child directories, and the concept listing. Run it first when picking up
an existing bundle: it is the cheapest high-signal orientation, and it surfaces
enumeration drift a grep can't (you can't grep for a listing entry that is *missing*).

`--dir PATH` narrows to a directory **and everything below it**, and is
**repeatable** — `--dir model --dir format` shows both; `root` (or `.`) names the
bundle root, unless the bundle really has a `root/` directory, which owns the
word. A `--dir` also brings the **chain from the root down to it**, so a branch is
never shown adrift of the authored context that says what it is — the root
`index.md`'s prose first among it. Those rows print with a leading `↑` and carry
`ancestor: true`; `--no-ancestors` drops them. Ascent and descent are separate
axes, so `--depth` never bounds the chain: `--dir X --depth 0` is X alone, plus
how you get to X. A `--dir` that names nothing gains no chain — a lone root row
would read as a partial answer to a query that matched nothing.

`--depth N` bounds how far below the starting point the map reaches
(the `--dir` when one is given, else the bundle root), counted **relatively**:
`--depth 1` is the top of the tree, `--dir X --depth 1` is one branch of it, and
the pair walks down a level at a time.

**On a bundle of any size the map is unreadable whole** — every directory is a
section, and even `--no-body` keeps one listing row per *concept* — so narrow
rather than paging it: `okf dirs` is the orientation, `--dir <branch> --depth 1`
is the step down into it,
and `--except body,listing` on top of either is the lean JSON skeleton. Full
`index` output on a few hundred concepts runs to hundreds of KB; the same map at
`--depth 1` is a couple of KB.

`--no-body` drops the prose to a
skeleton (headers, rollups, child pointers). For a directory that has concepts but
**no `index.md`**, the listing is **synthesized** from the concepts' descriptions
and tagged `(no index.md)` — §8 explicitly permits synthesizing a map on the fly.

It is a **read view**: advisory, always exit 0. A synthesized directory is a
*signal* (a map worth writing), never a defect — `index` emits no lint findings and
never fails a bundle. JSON: `{ bundle, count, directories: [{ dir, index_path,
present, synthesized, count, types, tags, subdirs, body, listing: [{ id, title,
description, type, tags }] }] }` — `ancestor` marks a row that is there to place
the branch rather than to answer about it.

## dirs — the bundle's clusters and their sizes

`okf dirs <dir>` lists every directory the bundle has — the ones holding
concepts, the ones carrying an `index.md`, and the empty intermediates that only
exist to connect the tree — with the number of concepts living **directly** in
each and the number in its **subtree**. A cluster *is* a directory here, so this
is the view that tells you what `--dir` can be pointed at and how much sits
behind each choice.

Two numbers, because one cannot answer the question. `count` is direct, so the
column sums to the bundle's concept total and a dir holding only sub-directories
reads `0` rather than a hidden rollup. `subtree` is defined as *exactly what
`--dir <that row>` returns*, so the row and the flag can never disagree — which
is also why the root's subtree is its own direct count (`.` is a prefix of
nothing). Without it a truncated listing is all zeroes at the top of a deep tree,
which is where you most need to know where the mass is. The human table shows the
second column only where some dir actually nests.

`--dir PATH` (repeatable) narrows to a directory and its subtree, and brings the
**chain up to the root** with it so the branch is placed rather than shown
adrift — those rows are marked `↑`, carry `ancestor: true`, and stay out of
`total` (`--no-ancestors` drops them). `--depth N` keeps only N levels below the
starting point — the `--dir` when one is given,
the bundle root otherwise. Relative, not absolute, so `--dir a/b --depth 1`
reads "a/b and one level under it" without your first working out how deep `a/b`
is. `--depth 0` is the starting point alone. A `--depth` that is not a whole
number is a usage error (exit 2).

**This is the first command to run on a bundle you do not know** — the same first
move [SKILL.md](../../SKILL.md) prescribes. `okf dirs <dir>` is one row per
directory, so its size tracks the tree rather than the concept count: it tells
you the shape and where the weight sits, `--depth 1` trims it further on a deep
bundle, and you then descend with `okf index --dir`, one level at a time.

The root prints `(root)` and stores `.` — the split every grouped view keeps, so
a table and its `--json` never disagree about which spelling is the data. JSON:
`{ bundle, total, count, dirs: [{ dir, ancestor, count, subtree, subdirs }] }`,
root first. `count` is rows printed, chain included; `total` sums the direct
counts of the rows you actually asked for, which is what keeps a row's `subtree`
equal to the `total` that `--dir` on that row returns.

