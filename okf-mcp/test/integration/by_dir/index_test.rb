# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class IndexTest < MCPIntegrationCase
    test "defaults are bounded: the root and its children, bodies and listings on" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "index", bundle: "knowledge")

      assert_equal 4, data["total"]
      assert_equal %w[. decisions runbooks services], data["dirs"].map { |row| row["dir"] }.sort

      root = data["dirs"].find { |row| row["dir"] == "." }
      assert root["present"]
      assert_match(/Acme Knowledge/, root["body"])
      refute_match(/okf_version/, root["body"], "the frontmatter is stripped")

      services = data["dirs"].find { |row| row["dir"] == "services" }
      assert_equal %w[services/billing services/search], services["listing"].map { |item| item["id"] }
      assert_equal({ "Service" => 2 }, services["types"])
    end

    test "a directory with no index.md is synthesized, listing still carried" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "index", bundle: "knowledge")
      decisions = data["dirs"].find { |row| row["dir"] == "decisions" }
      assert decisions["synthesized"]
      refute decisions["present"]
      assert_nil decisions["body"]
      assert_equal [ "decisions/ledger" ], decisions["listing"].map { |item| item["id"] }
    end

    test "dir descends one branch" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "index", bundle: "knowledge", dir: "services")
      assert_equal [ "services" ], data["dirs"].map { |row| row["dir"] }
    end

    test "bodies false drops the bodies, listing false drops the listings" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "index", bundle: "knowledge", bodies: false, listing: false)
      data["dirs"].each do |row|
        refute row.key?("body")
        refute row.key?("listing")
      end
    end

    test "an unknown dir is a tool error" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "index", bundle: "knowledge", dir: "attic")
      assert result.error?
      assert_match(/no directory "attic"/, result.text)
    end
  end
end
