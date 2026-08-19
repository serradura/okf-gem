# frozen_string_literal: true

# Pro — every enforcement check this bundle runs, as a library.
#
# THE CONTRACT — what survives an implementation swap:
#   Blocking checks fail CLOSED. If enforcement is missing or cannot run, the
#   call is refused, loudly. A gate that cannot check must not wave things
#   through.
#   Feedback checks fail LOUD. If enforcement is degraded, it says so in the
#   same channel it would use to refuse.
#   No check ever fails SILENT. A gate that is sometimes absent and does not
#   confess converts "unchecked" into "checked and fine", which is worse than
#   having no gate at all.
#
# Why Ruby, and not the shell version this replaces: that one parsed its event
# JSON with `jq`. With `jq` absent the parse yielded an empty path, every
# guard's `case "$path" in *.md)` fell through, and the gate exited 0 — the
# `verified:` write sailed past the most load-bearing gate in the repo, in
# silence. That is precisely the failure the contract forbids, and it was
# unreachable to fix in shell without reimplementing a JSON parser. Here the
# parser is stdlib. The only reachable runtime failure is `require "okf"`,
# caught below and refused loudly; a missing interpreter is caught one layer
# up, in .claude/hooks/run, because a script that cannot start cannot report.
#
# The entry point is `lib/okf/plugin.rb` — a Command subclass registered with
# OKF::CLI.register, which the kernel discovers by scanning installed gem specs.
# This gem ships no executable: `okf pro <cmd>` is the only door, and that is
# load-bearing rather than tidy. The scaffold's `.claude/hooks/run` dispatches to
# one absolute `okf` and refuses unless that binary identifies itself as the
# enforcer; a second entry point would be a second thing for the wrapper to
# recognise, on the one code path where being wrong means a gate waves an edit
# through.
#
# What that file may NOT do is hold the rescue this contract needs. See its own
# header: the `require "okf/pro"` it defers is itself what can fail, so the
# guard lives outside the require, in the Command, and not in CLI.run below.
#
# Kernel constants are fully qualified — `::OKF::Bundle`, never `OKF::Bundle`
# — for the reason okf-mcp records: OKF::Pro::CLI and the kernel's OKF::CLI
# share a name, and lexical lookup inside `module OKF` finds ours first.
#
# Files, and why each is separate:
#   bundle_root.rb  where the bundle is, given where the agent is
#   event.rb        the hook event — the only place untrusted input is parsed
#   target.rb       bundle root + edited path, or nil when a check cannot apply
#   board.rb        board.md as data: sections, the budget header, links, dates
#   log.rb          log.md as data: the snapshot line, newest day
#   pairing.rb      the board↔work invariants both directions, plus the one git shell-out
#   guards.rb       the trust rules — attestation, and the append-only record
#   shell_guard.rb  the same rules at the door a shell command comes through
#   records.rb      the append-only record, asked of git at the commit door
#   conformance.rb  okf validate + okf lint, in process
#   reconcile.rb    Rule 1
#   budget.rb       Rule 3 — the cap, and the dormancy question
#   closing.rb      Rule 2 — the stop gate, and the session banner
#   snapshot.rb     Rule 2's counters, derived — checker, never generator
#   state.rb        the readers' payload: what is on the board, in one call
#   conserve.rb     the write contract, enforced — line multisets in, refusals out
#   board/edit.rb   the board's text transforms, pure: text in, text out
#   log/edit.rb     the log's one text transform — a dated line under its day
#   writes.rb       the mechanical writers: read, transform, guard, rename
#   friction.rb     what the verbs did not cover, recorded — never enforced
#   attestation.rb  generated-without-verified listing; informs, never gates
#   audit.rb        the CI door: the same invariants minus the tool event
#   scaffold.rb     the generator: setup, upgrade, and the template beside it
#   cli.rb          dispatch, and the exit codes the hook protocol reads

# Kept deliberately conservative — nothing newer than 2.4, the floor okf takes
# from rack and this gem inherits. That floor matters more here than in any
# sibling: this code runs inside a git hook and a CI step on machines nobody
# chose, and a checker that cannot parse is a checker that is off.
#
# A SyntaxError exits 1, and the hook protocol reads a 1 as a non-blocking
# error: the edit proceeds. Syntax this file cannot parse is therefore syntax
# that fails OPEN, which the contract above forbids. The prototype's note that
# "no wrapper can catch it because nothing ran" was true of a wrapper that
# exec'd; the scaffold's does not, and catches it. The floor is still checked
# here for the case where the file parses but the interpreter is too old.
#
# Compared as versions, not strings: "10.0.0" < "2.4" is true lexicographically,
# so a string compare would refuse every edit on a future Ruby 10 — the gate
# blocking a perfectly capable interpreter, which is its own failure.
#
# The `exit 2` reaches the caller as a SystemExit through the require in
# OKF::CLI::Pro#call, which re-raises it rather than swallowing it: refusing
# is the whole point, and a rescue that turned this into a pass would be the
# fail-open the contract names.
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.4")
  warn "ENFORCEMENT DEGRADED — ruby #{RUBY_VERSION} is below this checker's 2.4 floor; " \
       "no check ran. Upgrade ruby, or every edit lands unchecked."
  exit 2
end

require "json"
# Date is used in nearly every module (Date.today defaults, Date.parse on board
# lines) but until now arrived only transitively, through the okf gem's yaml
# load. A constant the checker depends on and never requires is a NameError
# waiting for the day a dependency reorders its own requires — and the crash
# would land in session-context and the CI verbs, which sit outside the
# dispatch rescue.
require "date"

begin
  require "okf"
rescue LoadError
  warn "ENFORCEMENT DEGRADED — the `okf` gem is not loadable; no check ran. " \
       "Run `gem install okf`, or every edit lands unchecked."
  exit 2
end

module OKF
  module Pro
    # The hook protocol's vocabulary. 0 and 2 are the only codes it reads as
    # meaning anything; everything else is a non-blocking error, which is why
    # FAIL is reserved for `audit`, the one entry point that is not a hook.
    PASS  = 0
    BLOCK = 2 # PreToolUse: denies. PostToolUse: stderr returns to the agent. Stop: refuses to finish.
    FAIL  = 1 # audit only — CI's exit codes, not the hook protocol's.

    # Words too common to reconcile on. A search for "the" returns the corpus.
    STOP_WORDS = %w[the a an of and or for to in on with my is not].freeze

    # Every raw read the checker makes goes through here. Read as bytes,
    # forced to UTF-8, scrubbed — because the alternative failed open twice
    # over: with LANG unset (common in CI and git hooks) default_external is
    # US-ASCII and even a clean em dash raises on the first regex; and one
    # invalid byte anywhere raised ArgumentError out of match?, exiting the
    # checker with a code the hook protocol reads as NON-BLOCKING. A crash
    # is a pass, from the protocol's side — so the reader must not crash,
    # and (belt to this suspender) CLI.run refuses on anything that still
    # does.
    def self.read_text(path)
      File.read(path, mode: "rb").force_encoding(Encoding::UTF_8).scrub
    end

    # The same read, contained. Where the caller already HOLDS the bundle root,
    # this is the one to use: `SafeRead.read!` resolves the path and refuses one
    # whose symlinks leave the root, which is the kernel's containment primitive
    # and not a second implementation of it. `.scrub` stays ours, for the reason
    # above — `read!` tags the encoding without validating it.
    #
    # Not used where there is no root to contain against. `BundleRoot` is
    # deciding WHERE the root is, so it has none; and there a raise would be a
    # permanent lockout while a rescue would answer "not a root", mis-rooting
    # the bundle and disarming the journal guard.
    #
    # Callers rescue `Path::Error` themselves and choose the safe answer for
    # their own question, because "this file escapes the bundle" means something
    # different to a closure marker than it does to a journal entry.
    def self.read_contained(root, path)
      ::OKF::SafeRead.read!(root, path).scrub
    end

    # A final newline, guaranteed, before any transform splices a line in.
    # Without it an append after the file's last line concatenates onto it, and
    # a file whose last line is a board entry is exactly where an append lands.
    # Delta-free by construction: `Conserve` compares lines chomped, so adding
    # the terminator changes no key it can see.
    def self.newline_terminated(text)
      body = text.to_s
      return body if body.empty? || body.end_with?("\n")

      "#{body}\n"
    end

    # Files whose vocabulary is structural rather than conceptual. They are
    # excluded twice over — from being reconciled, and from being reported as
    # collisions — because they quote concepts rather than assert against them,
    # and a gate that reports the README every time is one people scroll past.
    NO_RECONCILE = %w[index.md log.md board.md CLAUDE.md README.md].freeze
  end
end

require "okf/pro/version"
require "okf/pro/bundle_root"
require "okf/pro/event"
require "okf/pro/target"
require "okf/pro/board"
require "okf/pro/board/edit"
require "okf/pro/log"
require "okf/pro/log/edit"
require "okf/pro/conserve"
require "okf/pro/friction"
require "okf/pro/pairing"
require "okf/pro/snapshot"
require "okf/pro/attestation"
require "okf/pro/guards"
require "okf/pro/shell_guard"
require "okf/pro/records"
require "okf/pro/conformance"
require "okf/pro/reconcile"
require "okf/pro/budget"
require "okf/pro/closing"
require "okf/pro/audit"
require "okf/pro/scaffold"
require "okf/pro/state"
require "okf/pro/writes"
require "okf/pro/cli"
