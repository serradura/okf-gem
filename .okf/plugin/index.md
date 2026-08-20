# The plugin

The repository is also a Claude Code **marketplace**, and `plugin/` is the thing
it offers. Three items, separate because they are installed, regenerated and
reviewed on different schedules.

None of it ships in any gem. `git ls-files` runs with `chdir:` into each gem's
directory and never sees the repository root, so this tree needs no reject entry
anywhere — worth knowing before someone adds one "for safety".

* [The Claude Code plugin](claude-code-plugin.md) - `plugin/` — one command, a generated copy of the skill, and a manifest that versions with the gem.
* [The curation hook](curation-hook.md) - `plugin/hooks/scripts/curate.rb` — plain Ruby on the stdlib, and the one file no gem's RuboCop reaches.
* [The marketplace manifest](marketplace.md) - `.claude-plugin/marketplace.json` — how the repository offers itself.
