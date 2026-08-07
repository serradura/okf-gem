# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class CatalogTest < MCPIntegrationCase
    test "resolves a registered slug with filters intact" do
      with_registry("knowledge", "notes") do
        data = call_tool!(mcp_server, "catalog", bundle: "notes", type: "Note")
        assert_equal 2, data["total"]
        assert_equal %w[billing-faq glossary], data["concepts"].map { |row| row["id"] }
      end
    end
  end
end
