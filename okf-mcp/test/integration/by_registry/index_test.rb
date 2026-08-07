# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class IndexTest < MCPIntegrationCase
    test "resolves a registered slug, defaults bounded" do
      with_registry("knowledge") do
        data = call_tool!(mcp_server, "index", bundle: "knowledge")
        assert_equal 4, data["total"]
        assert data["dirs"].find { |row| row["dir"] == "." }["present"]
      end
    end

    test "resolves the slug `as` renamed it to" do
      registry = OKF::Registry.load
      registry.add(fixture("knowledge"), as: "handbook")
      data = call_tool!(mcp_server, "index", bundle: "handbook", dir: "services")
      assert_equal [ "services" ], data["dirs"].map { |row| row["dir"] }
    end
  end
end
