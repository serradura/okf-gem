# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  # The `types` tool — tags' twin over the other index: every type with the
  # concepts carrying it, ordered by count. §4.1's vocabulary is open, so this
  # is how a consumer learns what a bundle's producer meant by its types.
  class TypesTest < MCPIntegrationCase
    test "every type with its concepts, ordered by count" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "types", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert_equal 3, data["total"]
      rows = data["types"]
      assert_equal %w[Service Decision Runbook], rows.map { |row| row["type"] }
      assert_equal %w[services/billing services/search], rows.first["concepts"]
    end

    test "an unknown bundle is a tool error naming it" do
      result = call_tool(mcp_server(fixture("knowledge")), "types", bundle: "nope")

      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end
  end
end
