# AGENTS.md

Maintainer guide for okf-pro — `okf-pro` on RubyGems. It turns an
[Open Knowledge Format](https://github.com/serradura/okf-gem) bundle into a
working memory an agent is held to: `okf pro setup` writes the bundle and the
governance around it, and `okf pro hook` runs one gate against one hook event.
This file documents how to change the code without breaking its contracts.

This gem is a sibling in the okf-gem monorepo, one directory per gem under
`gems/`, beside the baseline `gems/okf/` it depends on.
[`../../AGENTS.md`](../../AGENTS.md) is the repo-level
guide and owns everything above a single gem — the layout, the PR shape, the
release-title convention, the Git attribution rule. What is here is okf-pro's
own: the contract, the exit codes, the seam, and the scaffold. Where the two
overlap, the root is the general rule and this is the instance.

## Read the bundle first

**`.okf/` is this gem's structural documentation and its catalogue, and this
file no longer restates them.** What the code is, where each responsibility
lives, what every verb and check already answers, and how to add one all live
there — once, in the concept that owns them:

| you want | read |
| --- | --- |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, and it names every file |
| whether a capability already exists | [`.okf/capabilities/`](.okf/capabilities/) — sixteen verbs and nine checks, before you write a seventeenth |
| why a rule is a rule | [`.okf/design/`](.okf/design/) and [`.okf/contract/`](.okf/contract/) |
| how to add a verb or a check | [`.okf/testing/adding-a-verb.md`](.okf/testing/adding-a-verb.md) |
| what `setup` writes and who owns it | [`.okf/scaffold/`](.okf/scaffold/) |

`okf server .okf` from this directory reads it as a graph; `okf search @okf-pro
<term>` searches it from anywhere in the checkout.

The split used to run the other way: this file carried a hand-written Map of
`lib/**` and nothing checked it. `test/unit/bundle_catalog_test.rb` now fails
when a file under `lib/` is named by no concept, when a concept names a file
that is gone, or when either catalogue disagrees with `CLI::USAGE` and
`CLI::HOOK_NAMES` — so the structural layer is pinned where it lives, rather
than trusted where nobody looks.

## The contract, which outranks everything below it

> Blocking checks fail **closed**. If enforcement is missing or cannot run, the
> call is refused, loudly.
>
> Feedback checks fail **loud**. If enforcement is degraded, it says so in the
> same channel it would use to refuse.
>
> No check ever fails **silent**. A gate that is sometimes absent and does not
> confess converts "unchecked" into "checked and fine", which is worse than
> having no gate at all.

Every defect this gem has ever had failed in the direction of silence. A gate
that cannot run, a check that was skipped, a shim on `PATH`, a status code the
protocol reads as "proceed" — each produces an unchecked bundle that is
indistinguishable from a clean one. When you change anything here, the question
to ask is not "is this correct?" but "what does it do when it cannot answer?"

The argument in full, and the failures behind each clause, is in
[`.okf/contract/`](.okf/contract/the-contract.md).

## One door

This gem ships **no executable**. `lib/okf/plugin.rb` registers a `pro` command
with okf's registry, and `okf pro` is how a user gets here. That is load-bearing
rather than tidy, and more so than for the siblings that made the same call: the
scaffold's wrapper dispatches to **one** absolute `okf` and refuses unless that
binary identifies itself as the enforcer. A second entry point would be a second
thing for the wrapper to recognise, on the one code path where being wrong means
a gate waves an edit through. The seam is
[`.okf/structure/doors.md`](.okf/structure/doors.md).

## Hard constraints

1. **Ruby >= 2.4**, okf's own floor. It matters more here than anywhere else in
   the repo: this code runs inside a git hook and a CI step on machines nobody
   chose, and a checker that cannot parse is a checker that is off. The forbidden
   APIs are listed in [`../../AGENTS.md`](../../AGENTS.md); the ones this port had to
   undo were `filter_map` (2.7) and endless ranges (2.6). The floor is checked
   twice — in the gemspec, and at the top of `lib/okf/pro.rb`, which refuses
   with `exit 2` — and `test/unit/pro_test.rb` pins that the two agree.
2. **Runtime dependencies are exactly `okf`.** Everything else is stdlib. A
   gate with a dependency tree is a gate that fails to install on the machine
   that needed it most.
3. **`hook`'s exit codes are the protocol's, not this repo's.** `0` passes, `2`
   blocks, and **every other code — including `1` — is non-blocking**: the tool
   call proceeds. So `hook` never returns 1. Every other verb keeps the repo's
   0/1/2 convention, and `audit` in particular reserves 1 for *findings* and
   spells "the checker broke" as 2 — a pipeline that cannot tell those apart
   learns to ignore both. The table is in
   [`.okf/contract/exit-codes.md`](.okf/contract/exit-codes.md).
   Which is why **every verb in `CLI::READERS` routes through `parse_flags`**,
   listed in `FLAGS` or not: absence from that table means "accepts none", and a
   verb that skips the parser hands its undeclared flag to `BundleRoot.resolve`
   as a directory and reports "holds no OKF bundle" as a finding — a pipeline's
   own typo, spelled as a broken bundle. `test/integration/cli_test.rb` pins it
   over `READERS`, which is the invariant and the whole of it: the writers go
   through `writer_flags` instead (their first argument is content, so a flag
   there is data), and the scaffold verbs and `hook` through neither.
4. **The seam is where the contract's last Ruby line lives.** `plugin.rb` holds
   a `rescue Exception` that re-raises `SystemExit`, with the cop disabled and
   the reason beside it. That is not laziness: the failures it catches are
   `ScriptError`s, which are not `StandardError`s, and it must sit **outside**
   the `require "okf/pro"` it guards — inside `Pro::CLI.run` it could not
   catch the LoadError of the require that reaches it. See
   [`.okf/seam/three-fail-opens.md`](.okf/seam/three-fail-opens.md).
5. **A `SyntaxError` in `plugin.rb` is unreachable from Ruby.** Discovery
   rescues `LoadError, StandardError`; a `SyntaxError` is neither, the CLI dies
   with a parse dump and exit 1, and *no gem code runs at all*. Only the
   scaffold's `.claude/hooks/run` can catch it, which is why that wrapper no
   longer `exec`s. If you make it `exec` again, you have reopened this.
6. **`hook` whitelists its argument.** `Pro::CLI.run` dispatches the CI verbs
   off the same first argv element a check name arrives in, so an adapter that
   only stripped `hook` would make `okf pro hook audit` run a CI verb —
   measured status 0, "clean.", reading no stdin and never blocking. The
   whitelist is `Pro::CLI::HOOK_NAMES`, read from the library rather than
   copied, so it cannot drift from the composition table.
7. **The gate leaves no check silently unrun.** `Linter.call` with no options
   skips `expired` and `stale` and still reports `healthy?`. Supply what a check
   needs, or exclude it in source with its reason; never let
   `stats[:skipped_checks]` come back non-empty and be discarded.
   `test/integration/conformance_test.rb` asserts the residue is empty.
8. **A write verb is additive and targeted, never regenerative**, and that is
   enforced rather than promised. Each one computes its new text purely (in
   `board/edit.rb` or `log/edit.rb`, which cannot touch the disk), declares the
   delta it intends, and `Conserve` refuses with exit 2 — nothing written — if
   the actual delta differs in either direction. No verb writes a concept body
   or sets `verified:`; `snapshot` gains no `--write`, because a writer and a
   checker sharing a code path agree trivially. Agent text reaches a board line
   body or a journal entry body and nowhere else, and text spanning lines is
   refused rather than escaped — a verb invoked through Bash is seen by neither
   `guard-verified` nor `shell-guard`, so the safety is by construction. And a
   verb **refuses a missing file rather than writing one**: `capture` will not
   create `board.md`, `journal open` will not create `journal/index.md`, because
   an index rebuilt from the one line a verb knows is regeneration wearing an
   append's clothes. A name the caller supplies is contained twice over — one
   directory segment, *and* resolving inside the bundle, because
   `projects/<slug>` can be a symlink out and the checker that reads it refuses
   to. See
   [`.okf/design/derivation-that-writes.md`](.okf/design/derivation-that-writes.md)
   and [`.okf/contract/containment-directions.md`](.okf/contract/containment-directions.md).
9. **Friction is recorded at paths that already run, and never at a new hook
   event.** `.claude/settings.json` is seeded, so a registration added there
   would never reach an adopter through `upgrade`. The recorder refuses nothing
   and blocks nothing — and still may not report a zero it did not count: a
   failed write leaves a marker, an unwritable `.tmp/` is asked about directly,
   and an unparseable line is confessed. Nor may it ask for a verb nothing is
   missing: the session banner counts only rows an `okf pro` verb would answer
   (a shell redirect's answer is Edit or Write), and `--issue` prints nothing
   when nothing was recorded. It is telemetry about the tooling, so it is not
   one of `okf pro state`'s sources.
   [`.okf/contract/telemetry-does-not-lie.md`](.okf/contract/telemetry-does-not-lie.md).
10. **The scaffold splits by ownership, not by subject.** `upgrade` rewrites
    the four gem-owned files and never touches a seeded one. Reclassifying
    `CLAUDE.md`, `.gitignore` or `settings.json` as machinery makes `upgrade`
    destroy exactly the hand-merge `setup` told the adopter to perform. See
    [`.okf/scaffold/`](.okf/scaffold/ownership-not-subject.md).
11. **No date ships in the generated bundle**, outside a code span. The
    exemption is required rather than cosmetic — `projects/index.md` teaches the
    closure marker and `Pairing::MARKER` requires a date — and both directions
    of that coupling are pinned by `test/unit/closure_grammar_test.rb`.
12. **`lib/okf/pro/template/**` is what `setup` writes**, and it ships:
    `test/integration/scaffold_test.rb` compares the generated list against
    `spec.files`, *not* against a glob of the template, because a glob-versus-glob
    comparison ignores `.gitignore` on both sides and would pass in a checkout
    while the installed gem was short files. The `.gitignore` template is stored
    as `gitignore`, without the dot, for the same class of reason.

## Testing: drills first

The critical layer is `test/integration/wrapper_test.rb`, and it is unusual
enough to state plainly: **it runs the wrapper as a subprocess**, with a real
`PATH`, a real event on stdin, and the process's real exit status read back —
because the statements being tested are statements *about a process*, and none
of them is observable from inside one interpreter with injected streams. Every
drill there names a way the seam was found to break, and every one of them was a
gate that **passed**. The list, and why half the drills assert a *pass*, is
[`.okf/testing/drills-over-units.md`](.okf/testing/drills-over-units.md).

Beyond that, the repo's rules apply: one file per verb and subcommand, real
fixtures rather than mocks, a failing test before the fix, red for the reason
you predicted, then the same test green and unedited. The step-by-step walk a
new verb or check owes is
[`.okf/testing/adding-a-verb.md`](.okf/testing/adding-a-verb.md).

## Commands

```sh
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
ruby -Ilib -I../okf/lib ../okf/exe/okf pro audit .   # the CLI from the checkout
```

The Gemfile points `okf` at the checkout next door, so every run here — local,
CI, the floor container — resolves the checkout and nothing crosses to RubyGems
by default. Two things stand in that gap. `test/unit/gemspec_test.rb` is the
standing one: it fails the moment okf bumps and the declared floor does not
follow. And a run against the **published** kernel is the one that catches the
rest — this gem pins a frozen snapshot of okf's `Linter::SEVERITIES`, so a
released kernel that reclassified a check changes what the gate blocks on, which
is a difference no floor expresses:

```sh
sed '/gem "okf", path:/d' Gemfile > Gemfile.ci-check
BUNDLE_GEMFILE=Gemfile.ci-check bundle install && BUNDLE_GEMFILE=Gemfile.ci-check bundle exec rake
```

The 2.4 floor is proven the way the repo's is, from the root, stepping into this
gem:

```sh
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/gems/okf-pro && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

## Its own bundle

`.okf/` ships inside the gem, and `rake okf` at the repo root validates and
lints it. It carries two things the code cannot say for itself. The first is the
argument — the three fail-opens in the seam, the check the gate skipped in
silence, why identity is not existence, what the ownership split in the scaffold
is protecting. The second is the structure and the catalogue, which used to live
in this file and now live where a test can hold them to the code.

Maintain it in the same commit as the code it documents. A new file under `lib/`
without a line in the concept that owns its layer is a red suite, not a stale
document — and so is a verb added to `USAGE` without its row in the catalogue.
