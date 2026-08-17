# AGENTS.md

Maintainer guide for okf-pro — `okf-pro` on RubyGems. It turns an
[Open Knowledge Format](https://github.com/serradura/okf-gem) bundle into a
working memory an agent is held to: `okf pro setup` writes the bundle and the
governance around it, and `okf pro hook` runs one gate against one hook event.
This file documents how to change the code without breaking its contracts.

This gem is a sibling in the okf-gem monorepo, one directory per gem beside the
baseline `okf/` it depends on. [`../AGENTS.md`](../AGENTS.md) is the repo-level
guide and owns everything above a single gem — the layout, the PR shape, the
release-title convention, the Git attribution rule. What is here is okf-pro's
own: the contract, the exit codes, the seam, and the scaffold. Where the two
overlap, the root is the general rule and this is the instance.

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

## Map

```
lib/okf/pro.rb          the contract, the exit codes, the two reads, the requires
lib/okf/pro/
  bundle_root.rb   pure   where the bundle is, given where the agent is
  event.rb         pure   the hook event — the only place untrusted input is parsed
  target.rb        shell  bundle root + edited path, or nil when a check cannot apply
  board.rb         pure   board.md as data: sections, budget header, links, dates
  log.rb           pure   log.md as data: the snapshot line, the newest day
  pairing.rb       shell  the board↔work invariants both ways, plus the one git shell-out
  guards.rb        pure   the trust rules — attestation, and the append-only record
  shell_guard.rb   shell  the same rules at the door a shell command comes through
  records.rb       shell  the append-only record, asked of git at the commit door
  conformance.rb   shell  okf validate + okf lint, in process
  reconcile.rb     shell  Rule 1
  budget.rb        shell  Rule 3 — the cap, and the dormancy question
  closing.rb       shell  Rule 2 — the stop gate, and the session banner
  snapshot.rb      shell  Rule 2's counters, derived — checker, never generator
  attestation.rb   shell  what still awaits the owner's read
  state.rb         shell  the readers' payload — cheap by contract; --full is the one parse
  conserve.rb      pure   the write contract, enforced: line multisets in, refusals out
  board/edit.rb    pure   the board's text transforms, and the keyed selectors
  log/edit.rb      pure   a dated line, under its day, newest-first
  writes.rb        shell  the mechanical writers: read, transform, guard, rename
  friction.rb      shell  what the verbs did not cover, recorded — never enforced
  audit.rb         shell  the CI door: the same invariants minus the tool event
  scaffold.rb      shell  the generator: setup, upgrade, skill
  cli.rb           shell  dispatch, and the exit codes the hook protocol reads
  template/        the tree `setup` writes — gem/ (upgrade rewrites) + seed/ (yours)
lib/okf/plugin.rb  the okf extension seam, and the last Ruby-side line of the contract
```

`require "okf/pro"` loads everything: this gem is not an embedding library,
it is a checker, and every module is on the path of some gate.

**One door.** This gem ships **no executable**. `lib/okf/plugin.rb` registers a
`pro` command with okf's registry, and `okf pro` is how a user gets here.
That is load-bearing rather than tidy, and more so than for the siblings that
made the same call: the scaffold's wrapper dispatches to **one** absolute `okf`
and refuses unless that binary identifies itself as the enforcer. A second entry
point would be a second thing for the wrapper to recognise, on the one code path
where being wrong means a gate waves an edit through.

## Hard constraints

1. **Ruby >= 2.4**, okf's own floor. It matters more here than anywhere else in
   the repo: this code runs inside a git hook and a CI step on machines nobody
   chose, and a checker that cannot parse is a checker that is off. The forbidden
   APIs are listed in [`../AGENTS.md`](../AGENTS.md); the ones this port had to
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
`PATH`, a real event on stdin, and the process's real exit status read back.

That is not thoroughness for its own sake. The statements being tested are
statements *about a process* — "the protocol reads this as non-blocking", "the
shebang exits 127 when the interpreter is missing", "a bare locale makes
`Encoding.default_external` US-ASCII and an em dash raises" — and none of them
is observable from inside one interpreter with injected streams.

Every drill there names a way the seam was found to break, and **every one of
them was a gate that passed**. When you add a way for enforcement to be absent,
add its drill. When you fix one, the drill goes in first and fails for the
reason you predicted.

Half the drills assert a **pass**, and they are not optional: the event reaches
the check, an `ask` decision reaches stdout intact, the session banner survives,
the identity marker is stripped before anything downstream sees it. A wrapper
that refused everything would satisfy every refusal drill in the file.

Beyond that, the repo's rules apply: one file per verb and subcommand, real
fixtures rather than mocks, a failing test before the fix. Note that
`BundleFixture` is a **client of the code under test** — `write_log` computes
its snapshot line by calling the code — so "the suite is green, therefore
nothing changed" holds only for changes that do not touch what the fixture
calls. See [`.okf/testing/`](.okf/testing/fixture-is-a-client.md).

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
  "cp -a /src /build && cd /build/okf-pro && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

## Its own bundle

`.okf/` ships inside the gem, and `rake okf` at the repo root validates and
lints it. It carries what the code cannot say for itself: the three fail-opens
in the seam, the check the gate skipped in silence, why identity is not
existence, and what the ownership split in the scaffold is protecting. Maintain
it in the same commit as the code it documents.
