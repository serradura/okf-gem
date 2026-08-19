# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  # The `references` tool — the kernel's §6.3 inventory over MCP: every file
  # under references/ (the non-markdown ones no other tool can see), which
  # concepts cite each through the §6.2 path-valued fields, and the pointers
  # into references/ that resolve to nothing. Advisory like every read tool:
  # dangling pointers are data, never a tool error.
  class ReferencesTest < MCPIntegrationCase
    test "inventories the tree: paths sorted, kinds told apart, citers attached" do
      server = mcp_server(fixture("referenced"))
      data = call_tool!(server, "references", bundle: "referenced")

      assert_equal "referenced", data["bundle"]
      assert_equal 3, data["total"]
      rows = data["references"]
      assert_equal [ "references/attesters/revenue.py", "references/notes/scratch.txt",
                     "references/skills/run-on-bq.md" ], rows.map { |row| row["path"] }
      assert_equal %w[file file concept], rows.map { |row| row["kind"] },
        "a .md inside references/ is a first-class concept (§6.3 allows both)"
      assert_equal [ { "id" => "metrics/revenue", "field" => "attester.resource" } ],
        rows.first["referenced_by"]
      assert_equal [], rows[1]["referenced_by"], "the scratch notes are cited by nothing that resolves"
      assert_equal [ { "id" => "metrics/revenue", "field" => "executor.resource" } ],
        rows.last["referenced_by"]
    end

    test "a bare pointer written from a subdirectory dangles, with the leading-slash hint" do
      server = mcp_server(fixture("referenced"))
      dangling = call_tool!(server, "references", bundle: "referenced").fetch("dangling")

      assert_equal 1, dangling.length
      row = dangling.first
      assert_equal "metrics/revenue", row["id"]
      assert_equal "sources[0].resource", row["field"]
      assert_equal "references/notes/scratch.txt", row["raw"]
      assert_equal "metrics/references/notes/scratch.txt", row["resolved"]
      assert_equal "/references/notes/scratch.txt exists — missing leading slash?", row["hint"]
    end

    test "a bundle with no references/ tree answers an empty inventory, not an error" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "references", bundle: "knowledge")

      assert_equal 0, data["total"]
      assert_equal [], data["references"]
      assert_equal [], data["dangling"]
    end

    test "an unknown bundle is a tool error naming it" do
      result = call_tool(mcp_server(fixture("referenced")), "references", bundle: "nope")

      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end
  end
end
