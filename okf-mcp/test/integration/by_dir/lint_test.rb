# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class LintTest < MCPIntegrationCase
    test "the curation report: stats, findings, and a visible total" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge")

      assert_equal "knowledge", data["bundle"]
      assert_equal 4, data.dig("stats", "concepts")
      assert_equal data["findings"].length, data["total"]
      unlinked = data["findings"].select { |row| row["check"] == "unlinked" }
      assert_equal [ "services/search.md" ], unlinked.map { |row| row["path"] }
    end

    test "only and except select by check id" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", only: [ "unlinked" ])
      assert_equal [ "unlinked" ], data["findings"].map { |row| row["check"] }.uniq

      data = call_tool!(server, "lint", bundle: "knowledge", except: [ "unlinked" ])
      refute_includes data["findings"].map { |row| row["check"] }, "unlinked"
    end

    test "an unknown check id is a tool error naming the checks" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "lint", bundle: "knowledge", only: [ "rot" ])
      assert result.error?
      assert_match(/unknown check\(s\): rot/, result.text)
    end

    test "min_body flags stubs" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", min_body: 10_000)
      stubs = data["findings"].select { |row| row["check"] == "stub" }
      assert_equal 4, stubs.length, "every body is shorter than 10k characters"
    end

    test "stale_after takes a duration or an ISO date" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", stale_after: "1d", only: [ "stale" ])
      assert_equal 4, data["findings"].length, "every fixture timestamp is older than a day"

      data = call_tool!(server, "lint", bundle: "knowledge", stale_after: "2026-06-22", only: [ "stale" ])
      stale = data["findings"].map { |row| row["path"] }
      assert_includes stale, "services/search.md"
      refute_includes stale, "decisions/ledger.md", "timestamped after the cutoff"
    end

    test "an invalid stale_after is a tool error naming the accepted shapes" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "lint", bundle: "knowledge", stale_after: "soonish")
      assert result.error?
      assert_match(/invalid stale_after "soonish"/, result.text)
    end

    # The folder lens *is* the unlinked check, so the check-selection and
    # threshold options have nothing to act on. Silently ignoring them let a
    # caller read the full listing as though its filter had been applied.
    test "group folder refuses the options it cannot honour" do
      server = mcp_server(fixture("knowledge"))
      %i[only except min_body stale_after].each do |option|
        value = case option
                when :only, :except then [ "stale" ]
                when :min_body then 100
                else "90d"
                end
        result = call_tool(server, "lint", bundle: "knowledge", group: "folder", option => value)
        assert result.error?, "lint(group: \"folder\", #{option}: …) answered as if the option applied"
        assert_match(/folder/, result.text)
      end
    end

    test "group folder answers with the unlinked files by folder" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "lint", bundle: "knowledge", group: "folder")

      assert_equal "folder", data["group"]
      assert_equal 1, data["total"]
      assert_equal [ { "id" => "services/search", "title" => "Search", "dir" => "services" } ], data["files"]
    end
  end
end
