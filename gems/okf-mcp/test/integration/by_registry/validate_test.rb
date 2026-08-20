# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class ValidateTest < MCPIntegrationCase
    test "resolves a registered slug to the §9 verdict" do
      with_registry("scrappy") do
        data = call_tool!(mcp_server, "validate", bundle: "scrappy")
        refute data["conformant"]
        assert_includes data["errors"].map { |row| row["path"] }, "broken.md"
      end
    end
  end
end
