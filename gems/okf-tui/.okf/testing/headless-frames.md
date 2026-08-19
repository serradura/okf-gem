---
type: Playbook
title: Testing Frames Without a Terminal
description: How the suite drives real interactions and asserts on real frames with no pty — and the discipline of proving each check can actually fail.
tags: [testing, rendering]
timestamp: 2026-07-19
---

# The shape

Because [painting is a pure function of state](/rendering/whole-frame-painting.md),
a test needs no terminal — only a key script and a size:

```ruby
render(home: home, keys: "4<enter><tab>", size: [ 100, 30 ])
```

`keystrokes` maps `<enter>`, `<tab>`, `<esc>`, `<down>` to the real bytes, so a
script reads as what a user actually pressed. `app_for` drives `handle`;
`frame_for` renders through a `StringIO`; `FixedScreen` pins the size.

Bundles come from `with_registry`, which builds a temporary `$OKF_HOME`. Nothing
in the suite ever touches the real `~/.okf` — that is the user's configuration,
not the suite's.

# Prefer naming over counting

`app.open_concept("overview")` rather than three `<down>` presses. The list holds
reserved files as well as concepts, so cursor arithmetic is a guess about
ordering rather than a statement about which concept is open — and it breaks
whenever a fixture gains a file, in a way that looks like a real failure.

# Prove the check can fail

The discipline that mattered most here, because it repeatedly caught checks that
could not have failed:

- a geometry check reported "ok" on a frame that had **crashed** and rendered
  empty — zero rows trivially satisfied "every row is the right width";
- a check looped over the very constant it was testing, so it agreed with itself;
- a scroll check judged an offset against a different window than the view used,
  and reported a failure that was not real.

So: **sabotage the code, watch the check fail for the reason you predicted, then
restore it.** A green check that has never been seen red is an assumption wearing
a test's clothes.

The sharpest case was a whole suite that could not fail: 6,240 geometry
assertions that passed identically whether the layout measured columns or
characters, because every fixture was ASCII and the two numbers agree there.
Reducing `Ui.width` to `plain.length` was the sabotage that proved it — the
suite stayed green, and only a fixture of
[wide characters](/decisions/undeclared-width-dependency.md) turned it red. The same rule as the repo's test-first discipline, applied to
the harness itself — a bug report earns a red test before it earns a patch, and
the red has to be for the predicted reason, not a missing fixture or a typo'd
regex.

Assertions must also be read off real output: run it, read what it actually
prints, then assert *that*. Asserting what you assume the code does is how a
green suite certifies a bug.

# What this layer cannot catch

Two things, each covered elsewhere because no headless frame can reach them:

- a broken key loop, a raw-mode failure, or a binary that will not boot — that is
  [the pty test](/testing/pty-test.md);
- anything that depends on which okf actually resolves, since the Gemfile prefers
  the sibling checkout locally — that is [the CI matrix](/testing/ci-matrix.md).

# Citations

[1] `test/test_helper.rb` — `FixedScreen`, `with_registry`, `app_for`,
    `frame_for`, `keystrokes`.
