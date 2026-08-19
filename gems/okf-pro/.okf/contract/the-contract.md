---
type: Decision
title: The contract
description: Blocking checks fail closed, feedback checks fail loud, and no check ever fails silent — the three clauses every other decision in this gem is derived from.
---

# The three clauses

> Blocking checks fail **closed**. If enforcement is missing or cannot run, the
> call is refused, loudly. A gate that cannot check must not wave things through.
>
> Feedback checks fail **loud**. If enforcement is degraded, it says so in the
> same channel it would use to refuse.
>
> No check ever fails **silent**. A gate that is sometimes absent and does not
> confess converts "unchecked" into "checked and fine", which is worse than
> having no gate at all.

# Why the third clause is the one that matters

The first two are ordinary defensive engineering. The third is the reason this
gem is shaped the way it is, and it is the one people argue with.

The argument against it is that a skipped check is not a failure — nothing went
wrong, one question simply was not asked. The argument for it is what a reader
does with the answer. A bundle reported clean is a bundle nobody looks at again.
If the report was clean because seven of nine checks ran, the reader has been
handed a false negative wearing the costume of a verdict, and there is no
subsequent moment at which they find out.

That is worse than no gate, because no gate is a state a person can reason
about. "We do not check this" produces caution. "We checked and it is fine"
produces none.

# Where each clause is kept

* Fail closed lives in [the wrapper](/seam/the-wrapper.md), because a Ruby
  checker structurally cannot refuse on its own absence — something already
  running has to do it.
* Fail loud lives in the CLI's refusal messages, which name the cause rather
  than a code.
* Fail silent is closed in two places: [the exit codes](/contract/exit-codes.md),
  and [what the linter did not run](/contract/silent-skips.md).
