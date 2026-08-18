# frozen_string_literal: true

require_relative "mcp_integration_case"
require_relative "http_harness"

# The SEP-2575 modern lifecycle over the WEBrick bridge — the sessionless
# single-exchange path a 2026-07-28 client drives. The bridge already serves
# it (the SDK routes on the protocol-version header; every buffered response
# walks the same path legacy ones do), so these tests pin behavior rather
# than fix it: the discovery answer, the envelope round-trip, and the cache
# hints this server's doctrine depends on.
class HTTPModernTest < MCPIntegrationCase
  include HTTPHarness

  MODERN = "2026-07-28"

  test "server/discover answers before any handshake: versions, capabilities, identity" do
    with_http_server do |port|
      response = modern_post(port, method: "server/discover", id: 1)
      assert_equal "200", response.code
      result = JSON.parse(response.body).fetch("result")
      assert_equal [ MODERN ], result["supportedVersions"]
      assert result.key?("capabilities"), "discovery carries the capability map"
      assert_equal "okf", result.dig("_meta", "io.modelcontextprotocol/serverInfo", "name")
    end
  end

  test "an envelope-carrying tools/call runs a tool without any initialize" do
    with_http_server do |port|
      response = modern_post(port, method: "tools/call", id: 2, name: "search",
        params: { name: "search", arguments: { terms: [ "invoices" ] } })
      assert_equal "200", response.code
      result = JSON.parse(response.body).fetch("result")
      refute result["isError"]
      data = JSON.parse(result.dig("content", 0, "text"))
      assert_operator data["total"], :>, 0
    end
  end

  # Bodies are read live from disk — that is this server's promise — so the
  # only honest cache hint is "do not cache". Today that is the SDK's own
  # default when the server configures no ttl_ms/cache_scope; this pin turns
  # the default into a decision, and fails loudly if either side ever drifts
  # toward caching a result the files underneath can outrun.
  test "modern results carry ttlMs 0 and a private scope — live reads must not be cached" do
    with_http_server do |port|
      response = modern_post(port, method: "tools/list", id: 3)
      result = JSON.parse(response.body).fetch("result")
      assert_equal 0, result["ttlMs"]
      assert_equal "private", result["cacheScope"]
    end
  end

  private

  # One modern POST: the protocol-version and Mcp-Method mirror headers on
  # the wire, the SEP-2575 `_meta` envelope in params — every modern request
  # carries it, `server/discover` included — and Mcp-Name mirrored for the
  # name-bearing methods.
  def modern_post(port, method:, id:, params: {}, name: nil)
    params = params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => MODERN,
        "io.modelcontextprotocol/clientCapabilities" => {}
      }
    )
    headers = { "MCP-Protocol-Version" => MODERN, "Mcp-Method" => method }
    headers["Mcp-Name"] = name if name
    post(port, { jsonrpc: "2.0", id: id, method: method, params: params }, headers: headers)
  end
end
