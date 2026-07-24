---
type: Constraint
title: Three extension points, one idiom
description: Linter checks, search engines and CLI verbs all register the same way — append-only, idempotent by id — and CLI discovery loads only okf-* gems, a namespacing convention first and a mild guard second.
resource: okf/lib/okf/cli.rb
tags: [architecture, cli, extensibility, search, registry, security]
timestamp: 2026-07-20T12:00:00Z
---

# Overview

The gem grows by registration, not by editing. Three seams take addons, and they
are deliberately the same shape:

| Seam | Registers | State |
|------|-----------|-------|
| `Search.register` | a [search engine](../capabilities/search.md) | shipped |
| `CLI.register` | a [command](../cli.md) — a verb `okf` answers to | shipped |
| `Linter.register` | a [lint check](../capabilities/linter.md) | planned |

One idiom, in all three: **append-only, idempotent by id**. A second
registration of an id already present is a no-op, so a double `require` cannot
double the registry and **an addon cannot quietly displace a built-in**. What
each admits is checked at registration rather than at use — a capability outside
the frozen vocabulary, a command that does not answer the duck type — so a
malformed addon fails where it is *installed*, not the first time somebody
reaches for it.

# Discovery is a convention, not a list

A gem extends the CLI by putting `okf/plugin.rb` on its load path and
registering from it. That is the entire contract. `Gem.find_latest_files` finds
it; nothing here names it.

The alternative — this gem keeping a list of the addons it knows about — was
rejected because it inverts who depends on whom. Every new addon would cost an
okf release, and the base gem would carry the names of things it does not
contain. Search set the precedent already: `--engine` reads the engine registry
at parse time, so an addon appears in `okf search --help` **without the CLI
knowing it exists**. A test greps `cli.rb` for addon names to keep it that way.

The one-way dependency is what makes it safe: `okf-tui` depends on `okf`, `okf`
depends on nothing of `okf-tui`, and discovery is by convention rather than
declaration — so there is no cycle to resolve.

# The trust boundary, and where it actually sits

`require` runs whatever it loads, so discovery-by-convention is a code-execution
decision and deserves to be argued rather than assumed.

The usual principle is that **Ruby's trust boundary is `gem install`, not
`require`** — by the time a package is on your disk, it has had its chance. That
is the reason `rubygems_plugin.rb`, Bundler's plugins and Minitest's
`minitest/*_plugin.rb` all load exactly this way and none is treated as a
vulnerability.

It is not quite the whole truth, and the gap is the part worth writing down:

| Gem | Executes at install? | Does a convention loader escalate? |
|-----|----------------------|-------------------------------------|
| native extension | **yes** — `extconf.rb` compiles | no; it already ran |
| pure Ruby | **no** — no post-install hooks | **yes**, narrowly: a gem that would sit inert now runs |

So the escalation is real and confined to one case — a pure-Ruby gem, installed
but never required. **That case is rarer than it first sounds**, and the honest
reading matters: a transitive dependency is required by its parent in normal
use, so if `foo` depends on `evil`, `require "foo"` already runs it. What is
left is a gem installed and then used by nothing at all. Two things bound even
that:

1. **Under Bundler, discovery is bundle-scoped.** `Gem.find_latest_files` sees
   only what the Gemfile resolved, so the Gemfile is already an allowlist. The
   exposure is a global `gem install okf` run outside a bundle.
2. **Only gems named `okf-*` are loaded** — see below, though the naming
   convention is the better reason for that rule than this one. Resolving the
   owning gem's name reads the spec's `full_gem_path`; naming an extension
   never runs it, and a test pins that.

   The rule has to hold *under failure* too, which is a separate claim and was
   once false. Enumerating the installed specs is what raises when one gemspec
   anywhere on the machine is corrupt — and the rescue answered `nil`, the same
   value that means "belongs to no gem" and is trusted. Every discovered path
   would have loaded, silently. A name that cannot be read is now its own
   answer, refused like any other, because a rule that switches itself off when
   it cannot get an answer is the false confidence this one is deliberately
   modest to avoid.

   The refusal carries its cause, which is the other half of holding under
   failure. Closing the door costs every extension on the machine at once, and
   "its owning gem could not be determined" on its own names no gem to fix and
   no reason to look — trading a silent wrong answer for an undiagnosable right
   one. The exception is reported with the refusal it caused.

   Three failure modes, then, and each had to be closed on its own. A path whose
   name is *refused* was the first. A lookup that *cannot answer* was the second.
   The third is the search itself failing, which has no path to hang a refusal on
   at all: `Gem.find_latest_files` raising once answered `[]` in silence, which
   reads exactly like a machine with nothing installed — the same fail-open as
   the second, one frame up, and it survived the fix to the second because the
   fix was aimed at the frame below it. It is reported on its own terms now.

   The lookup is also a single pass per discovery rather than one per path, and
   the failure memoizes with the result. Both halves are needed for the property:
   one outcome per discovery, so every path gets the same answer. Per-path
   enumeration made it a lottery — a failure that cleared between paths, a
   gemspec rewritten by a concurrent `gem install`, would refuse one path and
   trust the next in the same run. Caching only the success would have left that
   lottery standing in the one branch the change was written for. A test counts
   the passes, because "unlikely" and "unreachable" are not the same claim.

What the prefix cannot do is save anyone from a package they deliberately
installed under an `okf-` name. A typosquat is a `gem install` that already
happened; no loader rule undoes it.

# The `okf-` prefix is a convention first, a guard second

Stated plainly, because the reverse framing flatters it: **as a security control
the prefix earns very little** — it closes a window that is nearly empty, and
calling it a defence risks the false confidence that is worse than no rule.

It stays because it is a good **convention** on its own terms, which is how
Jekyll (`jekyll-*`), Vagrant (`vagrant-*`) and fastlane all namespace plugins.
It makes what counts as an okf extension explicit, findable on RubyGems, and
stops an unrelated gem claiming the `okf/plugin.rb` path by accident. Measured
cost: one pass over the installed specs per discovery — 1.0ms for 282 specs —
then 0.0002ms to resolve each discovered path against it, and nothing at all on
a run that discovers nothing.

The cost it does carry is on authors: an extension has to be *named* `okf-`
something, so an internal `acme-okf-ext` is refused rather than loaded. That is
the trade — a naming rule for a clear namespace — and it should be argued on
those terms if it is ever revisited, not on the threat model above.

**An allowlist was considered and rejected as disproportionate.** Recording
enabled extensions in `$OKF_HOME` — the shape `okf registry set` already uses for
bundles — would close the remaining window, at the cost of the property that
makes this seam worth having: installing the gem is the whole installation. The
window it closes is one the user opened themselves with `gem install`. If okf
ever grows an extension that runs with privileges the CLI does not already have,
this trade should be reopened.

# Lazy, because a one-shot CLI cannot afford eager

Discovery costs about 11ms on the [2.4 floor](ruby-floor.md). Small, and still
not worth paying on every run: `okf lint` resolves its verb against the registry
and dispatches **without scanning at all**. Only two paths pay — an unknown verb,
which has to look before it can fail, and `okf help`, which has to know
everything by definition.

This is the same arithmetic that made the scan the default
[search engine](search-engines.md): a process that loads a bundle, answers one
question and exits has nothing to amortize a fixed cost over. A CLI that refuses
to build an index for a single query should not pay for discovery to answer a
verb it shipped with.

Laziness has a second effect, unplanned but welcome. An addon that tries to claim
a built-in's verb is not merely refused — running that verb never loads it at
all. The refusal still has to hold for `okf help`, which does scan, and it does:
registration keeps the built-in and records the rejection.

# A broken addon is skipped, not fatal

The same [best-effort posture](../cli.md#best-effort-reads) the reader takes with
an unparseable file. A plugin that raises on load is caught, collected, and
reported on **stderr** — so a `--json` run's stdout stays a clean machine
substrate — and every other verb still works. One addon that will not load must
not cost a user their `okf lint`.

# What a command is

A `CLI::Command` subclass answering four questions about itself — `.id`,
`.group`, `.help_rows`, `.hidden?` — and one about a run: `#call(argv)`,
returning the exit status. Privacy is the boundary, which is the one idea worth
taking from Thor without taking Thor: `#call` is the whole public surface, so a
helper added to the base can never become a verb by accident.

There is no second, lesser interface for an addon. A plugin implements exactly
what a built-in does, because a seam only the base gem can use is not a seam.

# Why not Thor

Thor is the obvious reach, and the [Ruby 2.4 floor](ruby-floor.md) closes it:
Thor 1.3+ requires Ruby >= 2.6, and only the EOL 1.2.2 line accepts 2.4. Pinning
an old line for everyone is the mistake
[no version ceilings](../design/runtime-dependencies.md) already records as
having broken things once.

It would also be a fourth [runtime dependency](runtime-dependencies.md), which is
a design decision to be challenged rather than a convenience — and it would buy
little. What the CLI needed was a *registry*, not an option-parsing DSL; it
already has `optparse` from the stdlib, plus a help, exit-code and
stream-injection contract that Thor would fight rather than serve.

What Thor's ecosystem *did* supply is the structure: a base class holding the
shared surface, one file per command group, and privacy as the command boundary.
Those are ideas, and ideas are free.

# Citations

[1] [okf/lib/okf/cli.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/cli.rb) — `register`, `load_plugins`, the lazy dispatch, and `PLUGIN_FILE`.
[2] [okf/lib/okf/bundle/search.rb](https://github.com/serradura/okf-gem/blob/main/okf/lib/okf/bundle/search.rb) — the idiom this one copies.
[3] Verified 2026-07-19 on `ruby:2.4.10` (RubyGems 3.0.3): `Gem.find_latest_files` is present and answers in ~11ms; the full suite is green on the floor.
[4] Thor's ruby_version on RubyGems, 2026-07-19: 1.4.0 and 1.3.2 declare `>= 2.6.0`; 1.2.2 declares `>= 2.0.0`.
[5] Measured 2026-07-19: under `bundle exec`, `Gem.find_latest_files("okf/plugin.rb")` returned 0 with a sibling okf-tui checkout present but absent from the Gemfile; outside bundler it scans every installed gem (259 on that machine).
