# Kind over location

Kind: principle. Answers: how to organize folders, how an agent routes
by file kind, how to keep reorganization cheap.

What a file is must not be encoded only in where it lives. Each file
declares its kind in its first lines, and the index labels every entry
with that kind, so the agent routes on declared kind and directory
layout stays a free choice. <!-- rule: ss-kind-declared -->

## Mechanism

First line after the title, as plain prose:

    Kind: playbook. Answers: how to run a full maintenance pass.

Kinds worth distinguishing in a skill: index (routes), playbook (a
procedure to follow), reference (facts to consult), spec (normative
text). An agent asking "how do I..." wants a playbook; an agent asking
"what does X mean" wants a reference. The kind line is what lets it
choose without opening the file, via the index label.
<!-- rule: ss-kind-vocabulary -->

## Consequence

Because kind travels with the file, folders can be reorganized freely:
moving reference/cli.md into reference/verbs/ breaks nothing that
routing depends on, provided links are keyed per
rule ss-cite-keys and the index is regenerated. Location becomes an
ergonomic choice for humans, not a semantic commitment.
