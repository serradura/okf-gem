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
      USAGE = "usage: okf mcp [options] [<bundle-dir>|@slug ...]   " \
              "(no args: serve the bundles registered with `okf registry`)"

      DEFAULT_BIND = "127.0.0.1"
      DEFAULT_PORT = 9134

      # Two streams, because they carry different things. +out+ is the
      # diagnostic channel — the boot line, the notes, the refusals — and
      # defaults to stderr since stdout belongs to the stdio protocol. +stdout+
      # is the human channel the two informational flags use, and is a
      # parameter rather than a literal `$stdout` so the `okf mcp` verb can
      # hand over the streams the kernel injected into it.
      def self.run(argv, out: $stderr, stdout: $stdout)
        new(argv, out: out, stdout: stdout).run
      end

      def initialize(argv, out: $stderr, stdout: $stdout)
        @argv = argv
        @out = out
        @stdout = stdout
        @http = false
        @bind = DEFAULT_BIND
        @port = DEFAULT_PORT
        @allow_hosts = []
        @done = false
      end

      # Boot, then serve — structurally, because the two phases carry
      # different exit contracts and the rescue below must never see a serving
      # error. `SystemCallError` belongs in the boot rescue for the same
      # reason the tool wrapper rescues it: an errno is a fact about the
      # operator's machine, not a bug, and it must read as one line rather
      # than a backtrace. The bind is where it actually bites — `--http`
      # exists so one warm process is shared, which makes "that port is
      # already serving" the likeliest mistake, and it came back as eleven
      # frames and exit 1 while every other boot failure exited 2 with a
      # sentence. The HTTP bind happens *here*, in boot (see #prepare_http),
      # precisely so that stays true.
      def run
        server = nil
        begin
          args = parser.parse(@argv)
          return 0 if @done

          registry = args.empty? ? Registry.from_kernel : Registry.from_argv(args)
          registry.boot_notes.each { |note| say("okf-mcp: #{note}") }
          engine = Backend.detect
          server = Server.build(registry, engine: engine)
          announce(registry, engine)
          prepare_http(server) if @http
        rescue Error, OKF::Error, OptionParser::ParseError, SystemCallError, SocketError => e
          say("okf-mcp: #{e.message}")
          say(USAGE)
          return 2
        end

        serve(server)
      end

      private

      # Serving, past the boot rescue's reach. On stdio the likeliest errno is
      # the host closing its pipes — the session's normal end, not a mistake —
      # and nothing is printed: the streams belong to the host that just hung
      # up. The carve-out is exactly those two errnos, and stdio's alone: on
      # `--http` a hang-up errno cannot mean "the session ended" (boot output
      # already went through #say), and any other mid-serve errno on either
      # transport is a runtime fault hours past a valid invocation — it
      # propagates as the crash it is, never the usage banner's exit 2.
      def serve(server)
        @http ? @httpd.start : serve_stdio(server)
        0
      rescue Errno::EPIPE, Errno::ECONNRESET
        raise if @http

        0
      end

      # Diagnostics are best-effort: @out belongs to whoever spawned the
      # process, and a closed stderr must not decide the outcome — it did,
      # twice: the boot rescue's own puts re-raised EPIPE as a backtrace for
      # a normal hang-up, and the serve rescue filed a lost `--http` boot
      # line as a clean exit 0 for a server that never started.
      def say(line)
        @out.puts(line)
      rescue Errno::EPIPE, Errno::ECONNRESET
        nil
      end

      def parser
        OptionParser.new do |opts|
          opts.banner = USAGE
          opts.on("--http", "serve Streamable HTTP instead of stdio") { @http = true }
          opts.on("--bind HOST", "HTTP bind address (default #{DEFAULT_BIND})") { |value| @bind = value }
          opts.on("--port PORT", Integer, "HTTP port (default #{DEFAULT_PORT})") { |value| @port = value }
          opts.on("--allow-host HOST", "admit this Host header (repeatable; for a DNS name",
            "or a reverse proxy no local interface knows about)") { |value| @allow_hosts << value }
          opts.on("-h", "--help", "print this help") do
            @stdout.puts(opts)
            @done = true
          end
          opts.on("--version", "print the version") do
            @stdout.puts(VERSION)
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
        say("okf-mcp #{VERSION} — backend: #{engine.capabilities[:name]} — bundles: #{bundles}#{source}")
      end

      def serve_stdio(server)
        transport = ::MCP::Server::Transports::StdioTransport.new(server)
        server.transport = transport
        transport.open
      end

      # The bind, the traps and the boot line — everything that can fail as a
      # boot failure — so #run's rescue files an EADDRINUSE as the usage error
      # it is, while whatever #serve raises later is manifestly not boot.
      def prepare_http(server)
        require_relative "http"
        @httpd = HTTP.prepare(server, bind: @bind, port: @port, allow_hosts: @allow_hosts, out: @out)
      end
    end
  end
end
