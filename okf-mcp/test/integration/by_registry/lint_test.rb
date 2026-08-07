# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class LintTest < MCPIntegrationCase
    test "resolves a registered slug to the curation report" do
      with_registry("knowledge") do
        data = call_tool!(mcp_server, "lint", bundle: "knowledge", only: [ "unlinked" ])
        assert_equal [ "services/search.md" ], data["findings"].map { |row| row["path"] }
      end
    end
  end
end
