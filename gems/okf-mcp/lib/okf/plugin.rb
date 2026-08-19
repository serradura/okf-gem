# frozen_string_literal: true

require "okf/cli"

module OKF
  module MCP
    # `okf mcp` — this gem's entry point, and its only one.
    #
    # The gem has to be separate: the `mcp` SDK's floor is 2.7 against the
    # kernel's 2.4, and it brings five transitive dependencies to a tool whose
    # runtime set is deliberately three. None of that argues for a separate
    # *entry point*, which is what the plugin seam exists to avoid — the
    # dependency stays on this side of the line either way, since the verb
    # appears only on a machine that installed this gem, and a 2.4 machine
    # cannot install it at all (`required_ruby_version` sees to that).
    #
    # What it buys is discoverability: somebody who installed okf-mcp for their
    # agent host finds the server in `okf help` without having to know a second
    # command exists. There briefly *was* a second one — an `exe/okf-mcp` that
    # did nothing but call the same `CLI.run` — and it went before the first
    # release, while removing a name still cost nobody anything.
    class Command < ::OKF::CLI::Command
      def self.id
        :mcp
      end

      def self.group
        :extension
      end

      def self.help_rows
        [ [ "mcp       [<dir>|@slug…] [--http] [--port PORT]", "serve bundles over the Model Context Protocol" ] ]
      end

      # The SDK and its schema validator load *here*, not at the top of this
      # file: discovery requires this file for `okf help` and for every unknown
      # verb, so anything it pulls in at load time is paid for by runs that
      # never asked for a server. Deferring keeps that cost on `okf mcp` alone.
      #
      # Both streams are threaded through because the kernel's contract is that
      # a command writes nowhere but the streams it was handed — and stdio is
      # the protocol channel here, so a boot line escaping onto the real stdout
      # would corrupt the very first frame. `::OKF::MCP::CLI` is fully
      # qualified against the kernel's own `OKF::CLI`; two constants share the
      # name and only one of them serves MCP.
      def call(argv)
        require "okf/mcp"
        require "okf/mcp/cli"
        ::OKF::MCP::CLI.run(argv, out: @err, stdout: @out)
      end
    end

    ::OKF::CLI.register(Command)
  end
end
