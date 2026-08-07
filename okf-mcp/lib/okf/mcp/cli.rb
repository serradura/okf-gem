# frozen_string_literal: true

require "optparse"

require_relative "server"

module OKF
  module MCP
    # The argv-facing shell: parses options, builds the one server definition,
    # and hands it to a transport — stdio by default (each agent host spawns
    # its own process), --http for one warm process serving every agent. Exit
    # codes keep the kernel CLI's contract: 0 ok, 2 usage error. The boot line
    # goes to stderr because stdout is the stdio protocol channel.
    class CLI
      USAGE = "usage: okf-mcp [options] [<bundle-dir>|@slug ...]   " \
              "(no args: serve the bundles registered with `okf registry`)"

      DEFAULT_BIND = "127.0.0.1"
      DEFAULT_PORT = 9134

      def self.run(argv, out: $stderr)
        new(argv, out: out).run
      end

      def initialize(argv, out: $stderr)
        @argv = argv
        @out = out
        @http = false
        @bind = DEFAULT_BIND
        @port = DEFAULT_PORT
        @allow_hosts = []
        @done = false
      end

      def run
        args = parser.parse(@argv)
        return 0 if @done

        registry = args.empty? ? Registry.from_kernel : Registry.from_argv(args)
        registry.boot_notes.each { |note| @out.puts("okf-mcp: #{note}") }
        engine = Backend.detect
        server = Server.build(registry, engine: engine)
        announce(registry, engine)
        @http ? serve_http(server) : serve_stdio(server)
        0
      rescue Error, OKF::Error, OptionParser::ParseError => e
        @out.puts("okf-mcp: #{e.message}")
        @out.puts(USAGE)
        2
      end

      private

      def parser
        OptionParser.new do |opts|
          opts.banner = USAGE
          opts.on("--http", "serve Streamable HTTP instead of stdio") { @http = true }
          opts.on("--bind HOST", "HTTP bind address (default #{DEFAULT_BIND})") { |value| @bind = value }
          opts.on("--port PORT", Integer, "HTTP port (default #{DEFAULT_PORT})") { |value| @port = value }
          opts.on("--allow-host HOST", "admit this Host header (repeatable; for a DNS name",
            "or a reverse proxy no local interface knows about)") { |value| @allow_hosts << value }
          opts.on("-h", "--help", "print this help") do
            $stdout.puts(opts)
            @done = true
          end
          opts.on("--version", "print the version") do
            $stdout.puts(VERSION)
            @done = true
          end
        end
      end

      # The one-look diagnosis for "why these bundles?" and "why no ranked
      # results?": which backend answered detection, which bundles are served
      # under which slugs, and which registry file the names came from.
      def announce(registry, engine)
        bundles = registry.entries.map { |entry| "#{entry.slug} (#{entry.root})" }.join(", ")
        source = registry.source ? " — registry: #{registry.source}" : ""
        @out.puts("okf-mcp #{VERSION} — backend: #{engine.capabilities[:name]} — bundles: #{bundles}#{source}")
      end

      def serve_stdio(server)
        transport = ::MCP::Server::Transports::StdioTransport.new(server)
        server.transport = transport
        transport.open
      end

      def serve_http(server)
        require_relative "http"
        HTTP.serve(server, bind: @bind, port: @port, allow_hosts: @allow_hosts, out: @out)
      end
    end
  end
end
