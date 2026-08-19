---
type: Learning
title: Drills, not unit tests, at the enforcement seam
description: Every defect found in the entry point was a gate that passed while unable to check, which only a real process with a real exit status can catch.
---

# What a drill is here

A subprocess, a real `PATH`, a real event on stdin, and the process's real exit
status read back. Not a method call.

That is not thoroughness for its own sake. The statements being tested are
statements *about a process*: "the hook protocol reads this as non-blocking",
"the shebang exits 127 when the interpreter is missing", "a bare locale makes
`Encoding.default_external` US-ASCII and an em dash raises". None of them is
observable from inside one interpreter with injected streams.

# The list is the failure list

Each drill names a way the seam was found to break, and every one of them is a
gate that **passed**:

| Drill | Before |
|---|---|
| okf-pro's library unloadable | exit 1, edit proceeds |
| a syntax error in `plugin.rb` | exit 1, no gem code ran at all |
| a stray `okf` exiting 0 | exit 0, every gate off |
| `hook audit` | exit 0, "clean.", no stdin read |
| a bundled environment | unknown command, exit 2, gates absent |
| a project path with a space | exit 127, four gates disarmed |

None of them is a wrong answer. They are all *no answer*, wearing the costume of
a clean one — which is [the third clause](/contract/the-contract.md), from the
outside.

# And what must still get through

Half the drills assert a **pass**: the event reaches the check, an `ask`
decision reaches stdout intact, the session banner survives, the identity marker
is stripped before anything downstream sees it. A wrapper that refused
everything would satisfy every refusal drill in the table above.
