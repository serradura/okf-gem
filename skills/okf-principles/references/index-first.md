# Index first

Kind: principle. Answers: how to split a monolith, how to write an index,
what makes a description good, what an index must cover, how to verify a
split, what to do with a monolith you do not own.

The principle is not "split files". It is: the reader decides what to
load before paying for it. Splitting is only the mechanism; the index is
the contract. <!-- rule: ss-reader-decides -->

## What the index must do

Each entry carries a title, a one-line description, and a link. The
description must be discriminating: it lets an agent confidently skip
the file, not merely recognize it. Test each description by asking
"given a realistic question, does this line alone tell the agent whether
the answer is inside?" <!-- rule: ss-discriminating-descriptions -->

Good: `search - ranked text retrieval over metadata and body; exact by
default, two engines`. An agent with a search question opens it; an agent
with a validation question skips it with confidence.

Bad: `search - documentation for the search feature`. Recognizable, not
discriminating. It costs a read to find out.

Coverage must match the index's claim, not the author's interests. An
index that claims a whole document maps all of it, including the
sections a typical question never reaches - an index that quietly drops
what it judges uninteresting misroutes the reader who wanted exactly
that, and unlike a bad description, the gap is invisible: nothing on the
page says the section exists. Check this whenever an index is promoted
from inside a file to beside it, because a table scoped to its old
host's readers inherits that scope silently while its new claim widens.
<!-- rule: ss-coverage-matches-claim -->

## Where to split

Split along question boundaries, not file size: one file per family of
questions (per verb, per workflow, per spec section). A 500 line file
answering one family beats five 100 line files loaded together.
<!-- rule: ss-question-boundaries -->

The failure mode to check after any split: if a typical question now
requires loading multiple fragments where it used to load one region of
one file, the boundary is wrong. Measure before and after with a fixed
question set. <!-- rule: ss-fanout-check -->

The measurement, concretely: write ~10 realistic questions before
splitting, record which files and how many bytes each one needs under
the old structure, repeat after, and judge the worst question, not the
mean - the mean rewards lucky guessing inside a monolith, and a split's
real win is bounding the worst case. A question that got more expensive
names the boundary to merge back. <!-- rule: ss-measure-worst-case -->

A topic that moves out of the file where readers have long found it
keeps pulling them to the old address - measured splits misroute at
exactly these seams. Leave a one-line pointer at the old location
naming where the topic went. This is the tombstone discipline
(rule ss-tombstone) applied to relocated content instead of renamed
keys. <!-- rule: ss-seam-pointers -->

## Content you do not own

A monolith that is vendored, generated, or otherwise third-party is
never split, however large: splitting breaks re-vendoring, forks the
upstream, and voids any verbatim claim it carries. The index goes
beside it as a sibling file, mapping its internal structure (section
numbers, headings) from outside. If the document numbers its own
sections, those numbers are already the stable keys - cite them instead
of minting rule IDs into a file you cannot edit.
<!-- rule: ss-index-beside-foreign -->

## Layering

Three layers, cheapest first:

1. The index: always safe to load, tells you what exists.
2. One chosen file: loaded because its description matched the question.
3. Everything else: never loaded by default.

Reader instruction to include in the skill: "Read the index, choose the
one file the question calls for, and stop. Load a second file only when
the first names it as a prerequisite."
