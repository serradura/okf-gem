# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class ReadConceptTest < MCPIntegrationCase
    test "resolves a registered slug to the file verbatim" do
      with_registry("knowledge") do
        result = call_tool(mcp_server, "read_concept", bundle: "knowledge", id: "decisions/ledger")
        refute result.error?
        assert_equal read_utf8(File.join(fixture("knowledge"), "decisions", "ledger.md")), result.text
      end
    end
  end
end
