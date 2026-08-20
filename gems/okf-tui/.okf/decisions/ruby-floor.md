---
type: Decision
title: Ruby 2.4 Floor, Inherited
description: okf-tui takes okf's floor rather than its own, which costs the ergonomic syntax and forces the development tooling to load conditionally.
tags: [ruby-floor, dependencies]
generated:
  by: human:maintainer
  at: 2026-07-18
sources:
  - title: "`okf-tui.gemspec`, `Gemfile`, `Rakefile`."
    resource: https://github.com/serradura/okf-gem/blob/main/gems/okf-tui/okf-tui.gemspec
  - title: "Verified in `ruby:2.4` (Docker) and on CI, which runs 2.4 through 4.0."
    resource: "Verified in `ruby:2.4` (Docker) and on CI, which runs 2.4 through 4.0"
---

# Overview

`required_ruby_version = ">= 2.4.0"`, taken from okf (`@okf design/ruby-floor`),
which takes it from rack. A UI over a library that runs on the Ruby an OS
already ships would be a strange thing to require a newer Ruby for.

The cost lands in two places that are not obvious until you hit them.

# The port had to give up keyword_init

The prototype built its one-off structs the modern way:

```ruby
Prompt = Struct.new(:kind, :label, :buffer, :subject, :free_text, keyword_init: true)
```

`keyword_init:` is Ruby **2.5**. RuboCop at `TargetRubyVersion: 2.4` parses this
happily — it catches *syntax*, not *APIs* — so nothing local complained; it would
have failed on the floor at runtime. It is now a plain class with an
`attr_reader` and a `free_text?` predicate.

This is the general trap: the floor is a library-API constraint that only two
things actually prove — reading the version each method arrived in, and running
the suite on 2.4.

# The tooling cannot install on the floor it guards

RuboCop needs Ruby ≥ 2.5, so requiring it unconditionally makes `bundle install`
fail on 2.4 — the tooling that enforces the floor blocks the floor. Both dev gems
load conditionally, and the Rakefile degrades to test-only when RuboCop is
absent:

```ruby
if RUBY_VERSION >= "2.7"
  gem "irb"
  gem "rubocop", "~> 1.21"
end
```

So on 2.4 the *suite* is the proof and lint is skipped; on 2.7+ the default task
runs both. Same split okf uses, and it is why
[the CI matrix](/testing/ci-matrix.md) — not RuboCop — is what actually holds
the floor.

Nothing is pinned *down* to make this work — see
[no-version-ceilings](/decisions/no-version-ceilings.md).
