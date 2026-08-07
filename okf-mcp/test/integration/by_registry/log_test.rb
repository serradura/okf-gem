# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class LogTest < MCPIntegrationCase
    test "resolves a registered slug, root log first" do
      with_registry("knowledge") do
        data = call_tool!(mcp_server, "log", bundle: "knowledge")
        assert_equal %w[log.md runbooks/log.md], data["logs"].map { |row| row["path"] }
      end
    end
  end
end
