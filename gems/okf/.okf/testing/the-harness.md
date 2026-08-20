---
type: Component
title: The test harness
description: One base class for the whole suite — plain Minitest plus `test "..."` and block setup/teardown — and it runs on 2.4, so the gem's API floor binds the tests exactly as it binds `lib/`.
resource: gems/okf/test/test_helper.rb
tags: [testing, minitest, ruby-floor]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
---

# One base class

Every test in this gem subclasses `OKF::TestCase`, defined in
`test/test_helper.rb`. It is plain Minitest with two pieces of sugar:

* `test "a sentence" do … end` instead of `def test_a_sentence`, so a failure
  names the behaviour in prose rather than in snake case;
* block `setup` / `teardown`, which compose rather than requiring `super`.

Nothing else is the base class. A test that reaches for `Minitest::Test`
directly loses both and reads unlike its neighbours, which is the whole reason
the sugar exists — the three siblings each ported the same class for the same
reason, so the suites read alike across the monorepo.

# It runs on 2.4, so the floor binds it

The suite runs on every supported Ruby, 2.4 included. That makes the
[Ruby floor](../design/ruby-floor.md)'s forbidden-API list a rule about `test/`
as much as about `lib/` — a `filter_map` in a test fails the floor container
exactly as one in a source file does, and RuboCop will not catch either.

SimpleCov is the one exception, and it is conditional rather than absent: it
needs 2.5+, so `test_helper.rb` loads it inside a `begin`/`rescue` and the suite
simply runs without coverage where it cannot load. Coverage is a reporting
convenience; the floor is a contract, and the contract wins.

# What a test may assume about the disk

Fixtures are real directories under `test/fixtures/`, not mocks. A branch that
no fixture can reach is a branch nobody has ever proven, so the answer to an
unreachable path is a new fixture rather than a bent assertion — the general
form of that obligation is `@okf-eco design/how-a-change-is-proven`, and how the
critical layer is organised is
[integration first](../design/integration-first.md).
