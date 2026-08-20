# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class SearchTest < MCPIntegrationCase
    test "searches one registered bundle by slug" do
      with_registry("knowledge", "notes") do
        data = call_tool!(mcp_server, "search", terms: [ "invoices" ], bundle: "knowledge")
        assert_equal [ { "slug" => "knowledge", "dir" => fixture("knowledge") } ], data["bundles"]
        assert(data["results"].all? { |row| row["bundle"] == "knowledge" })
      end
    end

    test "omitting bundles searches every registered bundle" do
      with_registry("knowledge", "notes") do
        data = call_tool!(mcp_server, "search", terms: [ "invoices" ])
        assert_equal %w[knowledge notes], data["bundles"].map { |row| row["slug"] }
        assert_includes data["results"].map { |row| row["bundle"] }.uniq.sort, "notes"
      end
    end

    test "an unknown slug is a tool error naming the known ones" do
      with_registry("knowledge") do
        result = call_tool(mcp_server, "search", terms: [ "x" ], bundle: "nope")
        assert result.error?
        assert_match(/unknown bundle "nope" — known: knowledge/, result.text)
      end
    end
  end
end
