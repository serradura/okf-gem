# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  # The `stats` tool — the sizing rollup: how big is what I am about to read,
  # in one bounded answer. The two dir keys deliberately speak two languages —
  # `by_dir` is the disk (the kernel's directory_index), `by_top_dir` rolls up
  # the id — the recorded identity-vs-physical split, stated in the tool text.
  class StatsTest < MCPIntegrationCase
    test "the bundle rollup: counts, distributions, cross-links" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "stats", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert_equal 4, data["concepts"]
      assert_equal 4, data["dirs"]
      assert_equal 3, data["top_dirs"]
      assert_equal 4, data["cross_links"]
      assert_equal 4, data["distinct_tags"]
      assert_equal({ "Service" => 2, "Decision" => 1, "Runbook" => 1 }, data["by_type"])
      assert_equal({ "services" => 2, "decisions" => 1, "runbooks" => 1, "." => 0 }, data["by_dir"])
      assert_equal({ "services" => 2, "decisions" => 1, "runbooks" => 1 }, data["by_top_dir"])
    end

    test "an unknown bundle is a tool error naming it" do
      result = call_tool(mcp_server(fixture("knowledge")), "stats", bundle: "nope")

      assert result.error?
      assert_match(/unknown bundle "nope"/, result.text)
    end
  end
end
