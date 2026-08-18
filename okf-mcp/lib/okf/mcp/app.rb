# frozen_string_literal: true

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
        options = { stateless: true, enable_json_response: true, max_request_bytes: MAX_REQUEST_BYTES }
        options[:allowed_hosts] = Array(allowed_hosts) if allowed_hosts && !Array(allowed_hosts).empty?
        options[:allowed_origins] = Array(allowed_origins) if allowed_origins && !Array(allowed_origins).empty?
        transport(server, options)
      end

      # Wires one transport to one server definition — the single site that
      # names the SDK class, shared with the WEBrick bridge.
      def transport(server, options)
        app = ::MCP::Server::Transports::StreamableHTTPTransport.new(server, **options)
        server.transport = app
        app
      end
    end
  end
end
