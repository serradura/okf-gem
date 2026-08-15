# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  # The `tags` tool — the kernel's inverted tag index, and with `by` the
  # vocabulary-curation view: tags regrouped per dir or type, each carrying its
  # within-group count beside its cross-group total, so a scattered tag and a
  # local one read differently.
  class TagsTest < MCPIntegrationCase
    test "the inverted index: every tag with its concepts, ordered by count" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "tags", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert_equal 4, data["total"]
      rows = data["tags"]
      assert_equal %w[payments core discovery oncall], rows.map { |row| row["tag"] }
      assert_equal 3, rows.first["count"]
      assert_equal %w[decisions/ledger runbooks/billing-restart services/billing], rows.first["concepts"]
    end

    test "by regroups per dimension, with within-group counts beside cross-group totals" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "tags", bundle: "knowledge", by: "dir")

      assert_equal "dir", data["by"]
      assert_equal 4, data["total"]
      runbooks = data["groups"].find { |group| group["dir"] == "runbooks" }
      payments = runbooks["tags"].find { |row| row["tag"] == "payments" }
      assert_equal 1, payments["count"], "within the group"
      assert_equal 3, payments["total"], "across the bundle — the scatter signal"
    end

    test "by takes the two concept dimensions only" do
      result = call_tool(mcp_server(fixture("knowledge")), "tags", bundle: "knowledge", by: "color")

      assert result.error?
    end

    test "an unknown bundle is a tool error naming it" do
      result = call_tool(mcp_server(fixture("knowledge")), "tags", bundle: "nope")

      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end
  end
end
