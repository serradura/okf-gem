---
description: Hand any OKF task to the okf skill — search, author, curate, or doctor a bundle
argument-hint: "[search|produce|migrate|maintain|refine|consume|curate|doctor|<okf-cli-verb>] [dir] [--flags]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

Invoke the okf skill that ships with this plugin, passing the arguments
("$ARGUMENTS") through unchanged. The skill's `SKILL.md` owns all routing —
its Commands table picks the playbook by the first word, its intent inference
handles free-form wording, and empty arguments land on the menu playbook
(orient, then recommend; never auto-run). Do not re-route, filter, or
summarize here: read the skill and follow it exactly as written.
