# AGENTS.md

okf-pro — the enforcement layer. It turns an OKF bundle into a working memory an
agent is held to: `okf pro setup` writes the bundle and the governance around it,
`okf pro hook` runs one gate against one hook event. A sibling in the okf
monorepo, beside the baseline `gems/okf/` it depends on.

**This file is context, routing and reference.** [`../../AGENTS.md`](../../AGENTS.md)
binds every change in the repo; what is below is okf-pro's own, and every
argument for it is in `.okf/` rather than here.

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

Every defect this gem has ever had failed in the direction of silence. When you
change anything here, the question to ask is not "is this correct?" but "what
does it do when it cannot answer?" The failures behind each clause are
[`.okf/contract/the-contract.md`](.okf/contract/the-contract.md).

## Where to read

| you want | read |
| --- | --- |
| what a file under `lib/` does | [`.okf/structure/`](.okf/structure/) — one concept per layer, naming every file |
| whether a verb or check already exists | [`.okf/capabilities/`](.okf/capabilities/) — sixteen verbs, nine checks |
| why a rule is a rule | [`.okf/contract/`](.okf/contract/), [`.okf/design/`](.okf/design/), [`.okf/seam/`](.okf/seam/) |
| what `setup` writes and who owns it | [`.okf/scaffold/`](.okf/scaffold/) |
| how to add a verb or a check | [`.okf/testing/adding-a-verb.md`](.okf/testing/adding-a-verb.md) |

`okf server .okf` reads it as a graph; `okf search @okf-pro <term>` from anywhere
in the checkout.

## Hard constraints

Twelve rules. Each line is the whole of what you must hold; the link is why.

1. **Ruby >= 2.4**, okf's floor, and it matters more here: this runs inside a git
   hook on machines nobody chose, and a checker that cannot parse is off. The
   list is `@okf design/ruby-floor`; the floor is checked in the gemspec *and* at
   the top of `lib/okf/pro.rb`, and `test/unit/pro_test.rb` pins they agree.
2. **Runtime dependencies are exactly `okf`.** A gate with a dependency tree
   fails to install on the machine that needed it most.
3. **`hook`'s exit codes are the protocol's**: `0` passes, `2` blocks, every
   other code including `1` is non-blocking, so `hook` never returns 1 —
   [`.okf/contract/exit-codes.md`](.okf/contract/exit-codes.md).
4. **Every verb in `CLI::READERS` routes through `parse_flags`**, listed in
   `FLAGS` or not — otherwise an undeclared flag reaches `BundleRoot.resolve` as
   a directory and a pipeline's typo is reported as a broken bundle.
   `test/integration/cli_test.rb` pins it over `READERS`.
5. **The seam holds the contract's last Ruby line.** `plugin.rb`'s
   `rescue Exception` must sit **outside** the `require "okf/pro"` it guards —
   [`.okf/seam/three-fail-opens.md`](.okf/seam/three-fail-opens.md).
6. **A `SyntaxError` in `plugin.rb` is unreachable from Ruby**, so only the
   scaffold's `.claude/hooks/run` can catch it — which is why that wrapper no
   longer `exec`s. Make it `exec` again and you have reopened this.
7. **`hook` whitelists its argument** from `Pro::CLI::HOOK_NAMES`, read from the
   library rather than copied — otherwise `okf pro hook audit` runs a CI verb and
   reports "clean." without reading stdin.
8. **The gate leaves no check silently unrun.** Never let
   `stats[:skipped_checks]` come back non-empty and be discarded —
   [`.okf/contract/silent-skips.md`](.okf/contract/silent-skips.md).
9. **A write verb is additive and targeted, never regenerative**, enforced by
   `Conserve` refusing with exit 2 when the actual delta differs from the
   declared one. A verb refuses a missing file rather than writing one, and a
   caller-supplied name is contained twice over —
   [`.okf/design/derivation-that-writes.md`](.okf/design/derivation-that-writes.md),
   [`.okf/contract/containment-directions.md`](.okf/contract/containment-directions.md).
10. **Friction is recorded at paths that already run, never at a new hook
    event**, and the recorder may not report a zero it did not count —
    [`.okf/contract/telemetry-does-not-lie.md`](.okf/contract/telemetry-does-not-lie.md).
11. **The scaffold splits by ownership, not by subject.** `upgrade` rewrites the
    four gem-owned files and never touches a seeded one —
    [`.okf/scaffold/ownership-not-subject.md`](.okf/scaffold/ownership-not-subject.md).
12. **No date ships in the generated bundle** outside a code span, and
    `lib/okf/pro/template/**` is what `setup` writes and must ship —
    [`.okf/scaffold/no-date-ships.md`](.okf/scaffold/no-date-ships.md).

**This gem ships no executable**, and here that is a safety property rather than
tidiness: the scaffold's wrapper dispatches to **one** absolute `okf` and refuses
unless that binary identifies itself as the enforcer —
[`.okf/structure/doors.md`](.okf/structure/doors.md).

**The critical layer is `test/integration/wrapper_test.rb`, and it runs the
wrapper as a subprocess** — real `PATH`, real event on stdin, real exit status
read back, because the statements under test are statements *about a process*.
Every drill names a way the seam broke, and every one of them was a gate that
**passed** — [`.okf/testing/drills-over-units.md`](.okf/testing/drills-over-units.md).

## Commands

```sh
bin/setup                          # install dependencies
bundle exec rake                   # test + rubocop — the default task, what CI runs
bundle exec rake test              # just the suite (SimpleCov report in coverage/)
ruby -Ilib -I../okf/lib ../okf/exe/okf pro audit .   # the CLI from the checkout

# against the published kernel — this gem pins a frozen snapshot of okf's
# Linter::SEVERITIES, so a released kernel that reclassified a check changes
# what the gate blocks on, which is a difference no floor expresses
sed '/gem "okf", path:/d' Gemfile > Gemfile.ci-check
BUNDLE_GEMFILE=Gemfile.ci-check bundle install && BUNDLE_GEMFILE=Gemfile.ci-check bundle exec rake
```

The 2.4 floor, from the repo root:

```sh
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build/gems/okf-pro && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

## Its own bundle

`.okf/` ships inside the gem and `rake okf` at the repo root keeps it clean. It
carries the argument — the three fail-opens in the seam, the check the gate
skipped in silence, why identity is not existence — and the structure and
catalogue a test holds to the code.

Maintain it in the same commit as the code. A file under `lib/` with no concept
naming it is a red suite, and so is a verb in `USAGE` with no catalogue row.
