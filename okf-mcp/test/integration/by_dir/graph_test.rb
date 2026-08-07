# frozen_string_literal: true

require_relative "../mcp_integration_case"

module ByDir
  class GraphTest < MCPIntegrationCase
    test "minimal is the default: lean nodes, edges, type and tag indexes, no bodies" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "graph", bundle: "knowledge")

      assert_equal "minimal", data["view"]
      assert_equal 4, data["total_nodes"]
      assert_equal data["edges"].length, data["total_edges"]
      node = data["nodes"].find { |row| row["id"] == "services/billing" }
      assert_equal "Billing", node["title"]
      refute node.key?("body"), "no full-body dump through MCP"
      assert_includes data.dig("types", "Service"), "services/billing"
      assert_includes data.dig("tags", "payments"), "services/billing"
    end

    test "hubs ranks by inbound links with the source dirs" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "graph", bundle: "knowledge", view: "hubs")

      assert_equal data["hubs"].length, data["total"]
      top = data["hubs"].first
      assert_equal "services/billing", top["id"]
      assert_equal 2, top["inbound"]
      assert_equal({ "decisions" => 1, "runbooks" => 1 }, top["by_top_dir"])
    end

    test "traffic collapses concepts into dirs with arcs and cohesion" do
      server = mcp_server(fixture("knowledge"))
      data = call_tool!(server, "graph", bundle: "knowledge", view: "traffic")

      assert_operator data["cut"], :>=, 1
      assert_equal data["arcs"].length, data["arcs"].length
      assert_operator data["total_arcs"], :>=, data["arcs"].length
      services = data["dirs"].find { |row| row["dir"] == "services" }
      assert services.key?("cohesion")
      assert services.key?("in")
      assert services.key?("out")
    end

    test "surfaces unparseable files rather than answering as if whole" do
      server = mcp_server(fixture("scrappy"))
      data = call_tool!(server, "graph", bundle: "scrappy")
      assert_equal 1, data["unparseable"]
    end

    test "an unknown view is refused by the schema, naming the three on offer" do
      server = mcp_server(fixture("knowledge"))
      result = call_tool(server, "graph", bundle: "knowledge", view: "everything")
      assert result.error?
      assert_match(/`\/view` is not one of: \["minimal", "hubs", "traffic"\]/, result.text)
    end
  end
end
