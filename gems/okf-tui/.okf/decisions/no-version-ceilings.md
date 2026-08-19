---
type: Decision
title: No Version Ceilings on the Markdown Stack
description: Pinning kramdown and rouge to their old lines to protect the Ruby 2.4 floor broke modern Ruby instead; the gems declare their own floors, so resolution handles it per-Ruby.
tags: [ruby-floor, dependencies]
generated:
  by: human:maintainer
  at: 2026-07-18
sources:
  - title: "`okf-tui.gemspec` — the two floors, with the comment recording the failed ceiling attempt."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/okf-tui.gemspec
  - title: "Verified in `ruby:2.4` (Docker): resolved kramdown 2.4.0 + rouge 3.30.0, 34 runs / 6622 assertions green, and green across the whole matrix up to 4.0."
    resource: "Verified in `ruby:2.4` (Docker): resolved kramdown 2.4.0 + rouge 3.30.0, 34 runs / 6622 assertions green, and green across the whole matrix up to 4.0"
---

# Overview

`tty-markdown` pulls in `kramdown` and `rouge`. Both have dropped Ruby 2.4 in
their current lines, so the first instinct was to pin everyone to the last
versions that still ran on the floor:

```ruby
spec.add_dependency "kramdown", ">= 2.3", "< 2.5"   # wrong
spec.add_dependency "rouge",    ">= 3.14", "< 4.0"  # wrong
```

That is backwards, and it broke the *modern* end of the matrix: kramdown 2.4
calls a `CGI` method that no longer exists on Ruby 4.0, so every job above the
floor died with `NoMethodError: undefined method 'parse' for class CGI`.

# The rule

**Do not pin a dependency down to protect an old Ruby.** A ceiling is a claim
about every Ruby, made to serve one of them.

The gems already carry `required_ruby_version`, and Bundler honours it: on 2.4 it
resolves kramdown 2.4.0 and rouge 3.30.0 by itself, on 4.0 it resolves the
current lines. Declaring only floors lets each Ruby get the newest version that
actually runs there — which is more than the ceiling would have allowed, and
correct on every Ruby rather than one.

```ruby
spec.add_dependency "kramdown", ">= 2.3"
spec.add_dependency "rouge", ">= 3.14"
```

This is the same reasoning that gates the *development* tooling instead of
pinning it — see [ruby-floor](/decisions/ruby-floor.md), where RuboCop and irb
load only on 2.7+ because they cannot install on the floor at all.

# The one ceiling, and what earns it

`okf` carries `< 3`, and it is not a hedge against a Ruby — it is the exception
that shows what the rule is actually about. The rule refuses a ceiling *made to
serve one Ruby*, because `required_ruby_version` already expresses that and
better. It does not refuse a ceiling that expresses a real incompatibility
resolution cannot see.

This one does, and the evidence is this gem's own scar tissue: an okf *major* is
where the renames come from, and those renames break screens
[silently](/decisions/okf-capability-drift.md) — `area` became `top_dir` and
every bundle reported one directory; `timestamp` became `generated_at` and the
"updated" row stopped rendering. Neither raised. Neither turned a suite red.

So `< 3` buys the one thing a floor cannot: it turns the *next* one into a
resolution failure a maintainer reads, instead of a wrong number a reader
believes. `test/unit/gemspec_test.rb` pins both bounds — the floor may never lag
the kernel this gem develops against, and the ceiling may not quietly go away.
