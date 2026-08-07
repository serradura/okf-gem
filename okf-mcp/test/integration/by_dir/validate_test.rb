# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class ValidateTest < MCPIntegrationCase
    test "a conformant bundle answers conformant with counts" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "validate", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert data["conformant"]
      assert_empty data["errors"]
      assert_equal 4, data.dig("counts", "concepts")
    end

    test "a broken file is a hard error naming the file and why" do
      server = mcp_server(fixture("scrappy"))
      data = call_tool!(server, "validate", bundle: "scrappy")

      refute data["conformant"]
      paths = data["errors"].map { |row| row["path"] }
      assert_includes paths, "broken.md"
    end
  end
end
