# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class ReadConceptTest < MCPIntegrationCase
    test "returns the concept verbatim, frontmatter and body" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "read_concept", bundle: "knowledge", id: "services/billing")
      refute result.error?
      assert_equal read_utf8(File.join(fixture("knowledge"), "services", "billing.md")), result.text
    end

    test "reads live from disk: an edit shows without a reboot" do
      dir = scratch_bundle("live")
      server = mcp_server(dir)
      before = call_tool(server, "read_concept", bundle: "live", id: "note")
      assert_match(/A scratch concept/, before.text)

      File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Scratch Note\n---\n\nRewritten just now.\n")
      after = call_tool(server, "read_concept", bundle: "live", id: "note")
      assert_match(/Rewritten just now/, after.text)
    end

    test "an unknown id is a tool error naming the finders" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "read_concept", bundle: "knowledge", id: "services/nope")
      assert result.error?
      assert_match(/ids are exact; find them with search or index/, result.text)
    end

    test "an unknown bundle is a tool error listing the known slugs" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "read_concept", bundle: "nope", id: "services/billing")
      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end
  end
end
