# Permissive reading

Kind: principle. Answers: how the agent should behave when structure is
missing or broken, how to migrate a skill incrementally.

A reader that refuses partial structure makes restructuring impossible,
because every real corpus is always partly migrated. The reader must
degrade, never stall. <!-- rule: ss-degrade-not-stall -->

## Reader-side rules to write into the skill

* An index entry pointing at a missing file is a note to surface, not a
  reason to stop. Fall back to searching the remaining files.
* A file the index does not list still counts. The index is a map, not
  an access control list.
* An unresolvable rule key gets reported verbatim so the author can fix
  it; the agent proceeds with its best reading.
* Unknown structure (an extra heading, an unrecognized comment, a new
  file kind) is preserved and ignored, never treated as an error.
  <!-- rule: ss-tolerate-unknown -->

## Author-side consequence

Because the reader tolerates gaps, migration can be incremental: split
one file, update the index, ship. The unmigrated remainder keeps working
as it did. This is the property that makes the other principles
adoptable at all; without it every restructuring is a big-bang rewrite.
<!-- rule: ss-incremental-migration -->
