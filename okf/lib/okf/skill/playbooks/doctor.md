# Playbook: set up the okf CLI and doctor the bundle

You are the installer and doctor for the Open Knowledge Format toolchain. Work
through the steps in order and report what you find at each one. Ask before any
install that touches the user's system; everything else, just do.

## 1. Is the CLI already here?

Run `okf --version`. If it prints a version, skip to step 3.

## 2. Install the gem

Find a Ruby first. The gem runs on any Ruby >= 2.4, so whatever the OS or a
version manager already ships will do:

- `ruby --version`; if absent, check the managers: `rbenv versions`,
  `asdf list ruby`, `mise ls ruby`.
- Repo has a Gemfile and okf belongs to the project? `bundle add okf`, then use
  `bundle exec okf` everywhere below.
- Otherwise: `gem install okf`.

Troubleshooting, in order of likelihood:

- `okf: command not found` right after a successful install: the gem bindir is
  not on PATH. `ruby -e 'puts Gem.bindir'` shows where the executable landed;
  add that to PATH, or refresh the manager's shims (`rbenv rehash`,
  `asdf reshim ruby`).
- Permission error on the system Ruby: do not reach for sudo. Use
  `gem install --user-install okf` and add `$(ruby -e 'puts Gem.user_dir')/bin`
  to PATH.
- Windows: a RubyInstaller Ruby works. Run the install from the same shell that
  has `ruby` on PATH, and note the executable is `okf.bat` under Gem.bindir.

Verify with `okf --version` before moving on.

## 3. Doctor the bundle

1. Locate a bundle: the directory you were given, if any; otherwise a `.okf/`
   directory, or a root `index.md` whose frontmatter carries `okf_version`.
2. Found one? Run `okf validate <root>` and `okf lint <root>`, then summarize
   in a few lines: conformant or not (and the errors if not), the warning
   count, and the top curation findings by category.
3. No bundle? Offer to bootstrap one. The okf skill knows how (its "produce"
   workflow); do not scaffold anything without the user's yes.

## 4. Say what changes now

Close with a short orientation. In Claude Code with the okf plugin active:
every Write or Edit that touches an OKF bundle runs `okf validate` and
`okf lint` automatically, and the findings come back as context to act on.
The checks are the CLI's own, so the feedback is deterministic. `/okf:gem
curate` runs the same cycle over the whole bundle on demand, and `/okf:gem`
with any other arguments (produce, maintain, consume, or a CLI verb) hands
the task straight to the skill. Without the plugin, the skill itself
instructs the agent to run the same checks after editing a bundle.
