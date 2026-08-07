# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class CatalogTest < MCPIntegrationCase
    test "per-concept metadata with link degrees, sorted by id" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge")

      assert_equal 4, data["total"]
      assert_equal %w[decisions/ledger runbooks/billing-restart services/billing services/search],
        data["concepts"].map { |row| row["id"] }

      billing = data["concepts"].find { |row| row["id"] == "services/billing" }
      assert_equal "Service", billing["type"]
      assert_equal %w[payments core], billing["tags"]
      assert_equal "active", billing["status"]
      assert_equal 2, billing["links_out"]
      assert_equal 2, billing["links_in"]
    end

    test "type, tag, dir and status narrow the rows" do
      server = mcp_server(fixture("knowledge"))

      data = call_tool!(server, "catalog", bundle: "knowledge", type: "Decision")
      assert_equal [ "decisions/ledger" ], data["concepts"].map { |row| row["id"] }
      assert_equal 1, data["total"]

      data = call_tool!(server, "catalog", bundle: "knowledge", tag: "oncall")
      assert_equal [ "runbooks/billing-restart" ], data["concepts"].map { |row| row["id"] }

      data = call_tool!(server, "catalog", bundle: "knowledge", dir: "services")
      assert_equal %w[services/billing services/search], data["concepts"].map { |row| row["id"] }

      data = call_tool!(server, "catalog", bundle: "knowledge", status: "accepted")
      assert_equal [ "decisions/ledger" ], data["concepts"].map { |row| row["id"] }
    end

    test "limit and offset slice while total stays the full count" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge", limit: 2, offset: 1)
      assert_equal 4, data["total"]
      assert_equal %w[runbooks/billing-restart services/billing], data["concepts"].map { |row| row["id"] }

      beyond = call_tool!(server, "catalog", bundle: "knowledge", offset: 10)
      assert_equal 4, beyond["total"]
      assert_empty beyond["concepts"]
    end

    test "fields projects each row down to the named keys" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "catalog", bundle: "knowledge", fields: %w[id type])
      data["concepts"].each { |row| assert_equal %w[id type], row.keys }
    end

    # The bundle root has four spellings and they must all mean the same
    # thing — and the same thing the other tools mean by them.
    test "\"/\", \".\" and \"root\" all name the bundle root" do
      server = mcp_server(fixture("notes"))
      direct = call_tool!(server, "catalog", bundle: "notes", dir: ".")["total"]
      assert_equal 2, direct

      assert_equal direct, call_tool!(server, "catalog", bundle: "notes", dir: "/")["total"]
      assert_equal direct, call_tool!(server, "catalog", bundle: "notes", dir: "root")["total"]
    end

    test "surfaces unparseable files rather than answering as if whole" do
      server = mcp_server(fixture("scrappy"))
      data = call_tool!(server, "catalog", bundle: "scrappy")
      assert_equal 1, data["total"]
      assert_equal 1, data["unparseable"]
    end

    test "an unknown field is a tool error naming the row keys" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "catalog", bundle: "knowledge", fields: [ "body" ])
      assert result.error?
      assert_match(/unknown field\(s\): body/, result.text)
    end
  end
end
