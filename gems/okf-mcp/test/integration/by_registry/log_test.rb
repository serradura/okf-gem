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

    test "the entry bound holds by ref too, and limit raises it" do
      with_registry("chronicled") do
        server = mcp_server
        bounded = call_tool!(server, "log", bundle: "chronicled")
        assert_equal 8, bounded["total"]
        assert_equal 3, bounded["logs"].first["returned"]
        refute_match(/First entry/, bounded["logs"].first["content"])

        whole = call_tool!(server, "log", bundle: "chronicled", limit: 10)
        assert_equal 6, whole["logs"].first["returned"]
        assert_match(/First entry/, whole["logs"].first["content"])
      end
    end
  end
end
