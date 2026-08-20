# frozen_string_literal: true

require "okf"

require_relative "mcp/version"
require_relative "mcp/filters"
require_relative "mcp/registry"
require_relative "mcp/memory_backend"
require_relative "mcp/backend"

module OKF
  # The MCP shell over the okf kernel — the fourth surface beside CLI, HTTP and
  # library. `require "okf/mcp"` loads the registry seam and the backends only;
  # the MCP SDK and the argv-facing pieces load on demand from `okf/mcp/server`
  # and `okf/mcp/cli` (the `okf mcp` verb requires the latter, inside #call),
  # so an embedding app never pays for the protocol machinery.
  module MCP
    class Error < StandardError; end

    # The Rack seam — the same server definition and stateless transport
    # `--http` serves, as the app a config.ru runs (`run OKF::MCP.app`).
    # Lazy, so requiring this file never pays for the protocol machinery.
    def self.app(refs = [], **options)
      require_relative "mcp/app"
      App.build(refs, **options)
    end
  end
end
