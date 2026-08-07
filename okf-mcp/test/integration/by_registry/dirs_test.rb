# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByRegistry
  class DirsTest < MCPIntegrationCase
    test "resolves a registered slug" do
      with_registry("knowledge", "notes") do
        data = call_tool!(mcp_server, "dirs", bundle: "knowledge")
        assert_equal 4, data["total"]
        assert_equal "knowledge", data["bundle"]
      end
    end

    test "a named slug whose directory vanished fails hard" do
      dir = scratch_bundle("goner")
      with_registry("knowledge") do |registry|
        registry.add(dir)
        FileUtils.rm_rf(dir)

        result = call_tool(mcp_server, "dirs", bundle: "goner")
        assert result.error?
        assert_match(/registered at .*goner, which is not a directory/, result.text)
      end
    end
  end
end
