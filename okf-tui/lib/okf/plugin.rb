# frozen_string_literal: true

# The extension point okf discovers: `okf/plugin.rb` anywhere on the load path.
# Installing this gem is the whole installation — `okf tui` works with no
# configuration, and `okf help` lists it. This gem ships no executable, so this
# file is the entry point rather than a second way in.
#
# okf loads this file, not the library. Everything expensive stays behind #call:
# the TTY toolkit, kramdown and rouge are a real cost to pay at boot, and this
# file is read whenever a verb misses or `okf help` runs. Registering a class
# costs nothing; building a terminal UI does.

require "okf/cli"

# An okf old enough to lack the command registry also lacks the discovery that
# would load this file, so in practice this is unreachable — it exists so that a
# hand-written `require "okf/plugin"` against one says what is wrong instead of
# raising NameError on a constant nobody was looking for. Raised rather than
# skipped: a plugin that silently declines to register is the failure mode this
# whole seam is meant to make impossible.
unless defined?(OKF::CLI::Command)
  raise LoadError, "okf-tui needs an okf with the CLI command registry (OKF::CLI::Command); this okf has none"
end

module OKF
  class CLI
    # `okf tui` — this gem's entry point, and its only one.
    #
    # The gem has to be separate: six TTY gems plus kramdown and rouge is a
    # dependency set the kernel's deliberate three has no business growing into.
    # None of that argues for a separate *entry point*, which is what this seam
    # exists to avoid. There briefly was one — an `exe/okf-tui` that did nothing
    # but call the same `CLI.run` — and it went before the first release, while
    # removing a name still cost nobody anything. What the seam buys instead is
    # discoverability: somebody who installed okf-tui finds it in `okf help`
    # without having to know a second command exists.
    class Tui < Command
      def self.id
        :tui
      end

      def self.help_rows
        [ [ "tui       [DIR|@slug…]", "browse bundles in a full-screen terminal UI" ] ]
      end

      # The heavy require lives here so that listing the verb stays cheap.
      #
      # `input` is why Command carries a terminal at all: every other verb is a
      # one-shot read that never looks at stdin, and this one cannot work
      # without it. Taking it from the command rather than reaching for $stdin
      # keeps the whole surface inside okf's stream injection — which is what
      # lets "it refuses to run without a terminal" be a test rather than a
      # hope.
      def call(argv)
        require "okf/tui/cli"

        ::OKF::TUI::CLI.run(argv, out: @out, err: @err, input: input)
      end
    end

    register(Tui)
  end
end
