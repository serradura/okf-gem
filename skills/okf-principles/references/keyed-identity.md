# Keyed identity

Kind: principle. Answers: how to make cross-references survive rewrites,
how to cite a rule from another file, how to name rule IDs.

Positional references (section numbers, "the third paragraph", quoted
prose, file-plus-heading paths) misattribute silently the moment an
agent rewrites or a file moves. A stable key travels with the content it
names. <!-- rule: ss-keys-not-positions -->

## Mechanism

An HTML comment on the paragraph that states the rule:

    Exact matching is the default because identifier queries are the
    common case. <!-- rule: myskill-search-exact-default -->

Invisible when rendered, greppable, and stable across file moves because
the key is attached to the paragraph, not to a location.

## Citing

Other files cite the key, never the path plus heading:

    Good: see rule myskill-search-exact-default
    Bad: see the search section of cli.md

The bad form breaks twice: when cli.md splits, and when the section is
renamed. The good form is resolved with one grep and survives both.
<!-- rule: ss-cite-keys -->

## Discipline

A published key is a contract. Renaming one breaks every citation, so:

* Prefix keys with the skill name to avoid collisions across skills that
  share a context window. <!-- rule: ss-key-prefix -->
* Key only rules worth citing from elsewhere. A key on every paragraph
  is noise; a key on every sharp edge, trap, and default is the target.
* When a rule is retired, leave a tombstone comment at the old key
  naming the replacement, for one release, so stale citations resolve to
  a pointer instead of nothing. <!-- rule: ss-tombstone -->
