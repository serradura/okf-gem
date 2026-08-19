---
type: Learning
title: A rule you can walk past is a preference
description: Why the gates block rather than warn, why three doors are not redundant, and why the day's ritual must stay silent on a day nobody worked.
---

# The claim

Every knowledge system that has ever failed its owner failed the same way: the
discipline was real for three weeks, then it was optional, then it was gone. A
warning you can dismiss is a preference with better typography, and the dismissal
becomes reflex faster than the habit does.

So the checks refuse. The edit does not land.

# What a refusal owes the person it stops

Three properties, and a message missing any of them trains people to route
around the gate rather than to comply with it:

* **It names the rule that fired.** Not "invalid" — the rule, by number and in
  words, so the refusal teaches the system it is enforcing.
* **It names the escape.** The cap is the adopter's own; going to six is
  allowed. What is forbidden is going to six *silently*. A rule with no
  legitimate exit gets disabled the first time it is genuinely wrong, and takes
  the rest of the gates with it.
* **It forces the comparison being avoided.** To promote a sixth thing you have
  to look at five commitments and say which is worth less. That comparison is
  the actual work of prioritisation, and without a ceiling nobody ever performs
  it — they only add.
* **The escape it names has to work.** The stop gate refuses a Snapshot line
  that disagrees with the board and prints the recomputed line, because the fix
  is a paste. A capture dated in the future gives a *negative* age; `render`
  wrote `oldest -365d` while the parse pattern demanded a digit straight after
  `oldest `, so the gate disagreed with the line it had itself just generated —
  and refused the paste it had just recommended. One mistyped year, and the only
  way out was to find a typo no gate was pointing at. A rule with no legitimate
  exit gets disabled the first time it is genuinely wrong; a rule whose *stated*
  exit does not work is that same failure with a false floor under it, because
  the reader spends their patience before they start looking.

  The repair is not to make the counter agree by making it lie. Clamping the age
  at zero would have made the gate self-consistent and `oldest 0d` unexplainable,
  which is the quiet-wrong-number failure derivation exists to refuse. A negative
  age is the honest reading of a future-dated capture, so both halves read it:
  render writes it and parse accepts it.

# Why three doors are not two too many

Each door sees edits the others structurally cannot. The agent hooks fire at the
tool boundary, so an edit made in an editor never reaches them — which is why
the commit door asks git directly. A clone that never ran `core.hooksPath` has
no commit door at all — which is why CI asks a third time. None of the three is
a belt-and-braces copy of another; each is the only witness to a class of edit.

# The counterweight: never bill a ritual for opening a file

A gate that fires on the calendar rather than on the work teaches people to
ignore it, and it is the same wolf-crying failure that
[Law 2](/design/three-laws.md)'s limit names. So the stop gate asks whether any
markdown in the bundle is actually dirty before it asks for anything: a session
that read the bundle and changed nothing closes in silence.

The confessed cost of that choice: a counter drifted by an editor edit stays
invisible until the next session stops, because `audit` checks that the day's
snapshot is present and not that its numbers are current. Preferring a
late-and-trusted gate to a punctual one nobody reads is the trade, made
deliberately.
