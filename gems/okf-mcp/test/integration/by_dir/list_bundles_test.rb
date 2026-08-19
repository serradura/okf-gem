# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class ListBundlesTest < MCPIntegrationCase
    test "lists argv bundles with slugs, rollups, backend and totals" do
      server = mcp_server(fixture("knowledge"), fixture("notes"))
      data = call_tool!(server, "list_bundles")

      assert_equal 2, data["total"]
      assert_equal "memory", data.dig("backend", "name")
      assert_nil data["registry_source"]
      assert_equal "knowledge", data["default"]

      knowledge = data["bundles"].find { |row| row["slug"] == "knowledge" }
      assert_equal fixture("knowledge"), knowledge["root"]
      assert_equal 4, knowledge["concepts"]
      assert_equal({ "Service" => 2, "Decision" => 1, "Runbook" => 1 }, knowledge["types"])
      assert_equal 3, knowledge["tags"]["payments"]
      refute knowledge.key?("missing")

      notes = data["bundles"].find { |row| row["slug"] == "notes" }
      assert_equal 2, notes["concepts"]
    end

    test "same basename dedupes with a suffix, argv order deciding" do
      copy = File.join(@out_dir, "deeper", "knowledge")
      FileUtils.mkdir_p(File.dirname(copy))
      FileUtils.cp_r(fixture("knowledge"), copy)

      server = mcp_server(fixture("knowledge"), copy)
      slugs = call_tool!(server, "list_bundles")["bundles"].map { |row| row["slug"] }
      assert_equal %w[knowledge knowledge-2], slugs
    end

    test "counts unparseable files instead of dropping them silently" do
      server = mcp_server(fixture("scrappy"))
      row = call_tool!(server, "list_bundles")["bundles"].first
      assert_equal 1, row["concepts"]
      assert_equal 1, row["unparseable"]
    end
  end
end
