# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class GraphTest < MCPIntegrationCase
    test "resolves a registered slug to the minimal view" do
      with_registry("knowledge") do
        data = call_tool!(mcp_server, "graph", bundle: "knowledge")
        assert_equal 4, data["total_nodes"]
      end
    end
  end
end
