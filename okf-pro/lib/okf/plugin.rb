# frozen_string_literal: true

# The extension point okf discovers: `okf/plugin.rb` anywhere on the load path.
# Installing this gem is the whole installation — `okf pro` works with no
# configuration, and `okf help` lists it. This gem ships no executable, so this
# file is the entry point rather than a second way in.
#
# okf loads this file, not the library. Everything expensive stays behind #call:
# this file is read whenever a verb misses or `okf help` runs, and registering a
# class costs nothing.
#
# THE REASON THIS FILE IS NOT THIN. Every sibling's plugin.rb is a require and a
# forward. This one holds the contract's last Ruby-side line, because the seam
# it sits on fails OPEN in three ways the sibling gems can afford and a gate
# cannot:
#
#   1. `okf/exe/okf` is `exit OKF::CLI.start(ARGV)` and CLI#dispatch calls
#      `#call` with no rescue. A LoadError out of the deferred
#      `require "okf/pro"` is a ScriptError — outside every rescue on the
#      path, including discovery's, which wraps only `require path` and catches
#      `LoadError, StandardError`. Measured: process exit 1, and the hook
#      protocol reads 1 as non-blocking, so the edit proceeds unchecked.
#   2. A check that returns something other than an Integer — or a CLI ported
#      from a standalone binary that calls `exit(true)` — lands on the same
#      hole: `exit(true)` is 0 and `exit(nil)` is 1, and neither is a verdict.
#   3. A SyntaxError in THIS file is not rescued by discovery either, for the
#      same ScriptError reason, and no code here runs at all. Nothing in Ruby
#      can catch that one; the scaffold's `.claude/hooks/run` is what does, and
#      it is why the wrapper stopped `exec`ing.
#
# So the rescue lives here, outside the require it guards, and not inside
# `Pro::CLI.run` — which cannot catch the LoadError of the require that
# reaches it, the very fail-open it would exist for.

require "okf/cli"

# An okf old enough to lack the command registry also lacks the discovery that
# would load this file, so in practice this is unreachable — it exists so that a
# hand-written `require "okf/plugin"` against one says what is wrong instead of
# raising NameError on a constant nobody was looking for. Raised rather than
# skipped: a plugin that silently declines to register is the failure mode this
# whole seam is meant to make impossible.
unless defined?(OKF::CLI::Command)
  raise LoadError, "okf-pro needs an okf with the CLI command registry (OKF::CLI::Command); this okf has none"
end

module OKF
  class CLI
    # `okf pro` — this gem's entry point, and its only one.
    class Pro < Command
      def self.id
        :pro
      end

      # ONE row, and the first row is the summary.
      #
      # `okf help` prints a map, not a manual: it says a verb exists and who
      # ships it, and `okf pro --help` is where this verb describes itself.
      # Eight rows here made the extensions block the longest section of that
      # map — longer than every built-in group — for a gem the reader may not
      # even have been looking for. The kernel now takes only the first row from
      # an extension, so declaring more would not print them; declaring one is
      # this side of the same decision, and keeps `help_rows` from claiming a
      # surface the map does not show.
      def self.help_rows
        [ [ "pro       <command> [DIR]", "scaffold an agent's knowledge repo, and enforce it at three doors" ] ]
      end

      # The whole public surface, and the whole of the Ruby-side guard.
      #
      # `rescue Exception` is the cop's textbook mistake everywhere else in this
      # repo, and it is the correct call exactly here: the failures this must
      # catch are ScriptErrors, which are not StandardErrors, and catching less
      # than Exception is the same as catching nothing. SystemExit is re-raised
      # rather than swallowed — `okf/pro.rb` refuses an under-floor Ruby with
      # `exit 2`, and a rescue that turned that refusal into an error report
      # would be the fail-open this method exists to close.
      #
      # rubocop:disable Lint/RescueException
      def call(argv)
        verb = argv.first.to_s

        return refuse_unknown_check(argv) if verb == "hook" && !hook_check?(argv[1])

        require "okf/pro"

        status = ::OKF::Pro::CLI.run(argv.dup.tap { |a| a.shift if verb == "hook" },
          stdin: input, stdout: @out, stderr: @err)

        # A non-Integer status is not a verdict, and `exit` would read it as one:
        # `exit(true)` is 0, `exit(nil)` is 1, and both are a gate saying nothing
        # while the protocol hears "fine".
        status.is_a?(Integer) ? status : blocked("returned #{status.inspect} instead of an exit status")
      rescue ::SystemExit
        raise
      rescue ::Exception => e
        blocked("#{e.class}: #{e.message}")
      end
      # rubocop:enable Lint/RescueException

      private

      # Whether the hook door accepts this name.
      #
      # The list it asks is `Pro::CLI::HOOK_NAMES`, deliberately NOT `NAMES`:
      # that one includes the CI verbs, and `Pro::CLI.run` dispatches them off
      # the same first argv element a check name arrives in. An adapter that
      # only stripped `hook` and forwarded would make `okf pro hook audit` run
      # the CI verb — measured status 0, "okf pro audit — clean.", reading no
      # stdin and never blocking. One typo in `settings.json` and the gate is a
      # gate that always says fine.
      #
      # Loading the library to answer this defeats the point of deferring it, so
      # the *check* is deferred instead of the answer: only a `hook` invocation
      # pays for the require, and the whitelist stays the composition table
      # rather than a second copy of it that can drift.
      def hook_check?(name)
        require "okf/pro"
        ::OKF::Pro::CLI::HOOK_NAMES.include?(name.to_s)
      rescue ::SystemExit
        raise
      rescue ::Exception # rubocop:disable Lint/RescueException
        # The library is unloadable, so the name cannot be validated — and an
        # unvalidated name must not be forwarded. Falling through to `#call`'s
        # own require reports the real cause.
        true
      end

      def refuse_unknown_check(argv)
        given = argv[1].nil? ? "no check name" : "'#{argv[1]}'"
        @err.puts "ENFORCEMENT MISCONFIGURED — `okf pro hook` was given #{given}. The hook door " \
                  "accepts only a check name; the CI verbs (audit, records, snapshot, unverified) " \
                  "are not gates and would report clean without reading the event at all. " \
                  "`okf pro --help` lists the checks."
        2
      end

      def blocked(cause)
        @err.puts "ENFORCEMENT DEGRADED — okf pro could not run (#{cause}); nothing was checked, " \
                  "so the call is refused. The hook protocol reads every code but 2 as " \
                  "non-blocking, which would let this through in silence."
        2
      end
    end

    register(Pro)
  end
end
