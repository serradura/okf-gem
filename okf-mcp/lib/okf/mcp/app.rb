# frozen_string_literal: true

require "json"

require_relative "server"

module OKF
  module MCP
    # The Rack seam: the same server definition and stateless transport the
    # `--http` verb serves, as the app a config.ru runs — so puma, unicorn or
    # any Rack server can host the bundles without this gem depending on one
    # (the reader's server is the reader's dependency; the no-rackup position
    # holds). This module owns transport construction; the WEBrick bridge
    # (okf/mcp/http.rb) builds through it, so the options exist in one place.
    #
    # Deliberately no listen cap here, unlike the WEBrick bridge's 32: under
    # a Rack 3 server a `subscriptions/listen` stream holds no thread — the
    # SDK's callable body returns immediately — so the SDK's own default is
    # the right bound.
    module App
      # The largest request body the transport reads, matching the SDK's own
      # StreamableHTTPTransport default.
      MAX_REQUEST_BYTES = 4 * 1024 * 1024

      # The MCP endpoint is the root and nothing else. The SDK transport
      # routes on method alone, so handed every path it answers a connecting
      # host's OAuth discovery probes (GET /.well-known/*, POST /register —
      # Claude Desktop sends both) with a 405 or a 200-wrapped JSON-RPC parse
      # error: a *broken* sign-in service instead of an absent one, and the
      # host refuses the connector on it. The WEBrick bridge scopes in its
      # own #handle; this wrapper is the same refusal for a config.ru host.
      class Scope
        def initialize(transport)
          @transport = transport
        end

        def call(env)
          path = env["PATH_INFO"].to_s
          # "" is the mounted spelling: `map "/mcp"` hands the mount point
          # itself an empty PATH_INFO.
          return not_found unless path.empty? || path == "/"

          @transport.call(env)
        end

        def close
          @transport.close
        end

        private

        def not_found
          [ 404, { "content-type" => "application/json" },
            [ JSON.generate(error: "not found: the MCP endpoint is /") ] ]
        end
      end

      module_function

      # +refs+ are argv-shaped bundle names — directories and @slugs, exactly
      # what `okf mcp` takes; empty serves the kernel registry, exactly like
      # `okf mcp` with no args. +allowed_hosts+/+allowed_origins+ widen the
      # SDK's DNS-rebinding allowlists for a reverse proxy or a DNS name; the
      # same posture as `--allow-host`, and the same warning — the allowlist
      # is not access control, and a Rack server bound beyond loopback
      # publishes every served bundle with no authentication.
      def build(refs = [], engine: nil, allowed_hosts: nil, allowed_origins: nil)
        registry = Array(refs).empty? ? Registry.from_kernel : Registry.from_argv(Array(refs))
        server = Server.build(registry, engine: engine || Backend.detect)
        Scope.new(transport(server, allowed_hosts: allowed_hosts, allowed_origins: allowed_origins))
      end

      # Wires one transport to one server definition. Every construction site
      # — this seam and the WEBrick bridge — goes through here, so the shared
      # posture (stateless, JSON responses, the body cap, the blank-allowlist
      # guard) is stated once and cannot drift between the two; a caller
      # passes only what is its own (the bridge: its listen cap).
      def transport(server, allowed_hosts: nil, allowed_origins: nil, **options)
        options = { stateless: true, enable_json_response: true,
                    max_request_bytes: MAX_REQUEST_BYTES }.merge(options)
        hosts = Array(allowed_hosts)
        options[:allowed_hosts] = hosts unless hosts.empty?
        origins = Array(allowed_origins)
        options[:allowed_origins] = origins unless origins.empty?
        app = ::MCP::Server::Transports::StreamableHTTPTransport.new(server, **options)
        server.transport = app
        app
      end
    end
  end
end
