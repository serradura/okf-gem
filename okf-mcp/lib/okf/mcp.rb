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
  # and `okf/mcp/cli` (exe/okf-mcp requires the latter), so an embedding app
  # never pays for the protocol machinery.
  module MCP
    class Error < StandardError; end
  end
end
