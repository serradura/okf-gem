# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/mcp/app"
require "stringio"

# The Rack seam, driven as a Rack server would: `app.call(env)` with
# hand-built envs, no socket and no WEBrick anywhere — proving what a
# config.ru gets is the whole point of these tests.
class AppTest < MCPIntegrationCase
  test "the app answers initialize like the served verb does" do
    app = OKF::MCP.app([ fixture("knowledge") ], engine: OKF::MCP::MemoryBackend.new)
    status, _headers, body = app.call(env_for(
      { jsonrpc: "2.0", id: 1, method: "initialize",
        params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "0" } } }
    ))
    assert_equal 200, status
    assert_equal "okf", JSON.parse(join(body)).dig("result", "serverInfo", "name")
  end

  test "no refs serves the kernel registry, exactly like `okf mcp` with no args" do
    with_registry("knowledge") do
      app = OKF::MCP.app(engine: OKF::MCP::MemoryBackend.new)
      status, _headers, body = app.call(tool_env(id: 2, name: "list_bundles"))
      assert_equal 200, status
      result = JSON.parse(join(body)).fetch("result")
      data = JSON.parse(result.dig("content", 0, "text"))
      assert_equal [ "knowledge" ], data["bundles"].map { |row| row["slug"] }
    end
  end

  # Under a Rack 3 server the streaming body is served natively — this pins
  # the shape a config.ru host receives, and that the callable speaks the
  # write/flush stream contract.
  test "subscriptions/listen hands a Rack streaming body that writes the acknowledgement" do
    app = OKF::MCP.app([ fixture("knowledge") ], engine: OKF::MCP::MemoryBackend.new)
    begin
      status, headers, body = app.call(env_for(
        { jsonrpc: "2.0", id: 5, method: "subscriptions/listen",
          params: { notifications: {},
                    _meta: { "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
                             "io.modelcontextprotocol/clientCapabilities" => {} } } },
        headers: { "HTTP_MCP_PROTOCOL_VERSION" => "2026-07-28", "HTTP_MCP_METHOD" => "subscriptions/listen" }
      ))
      assert_equal 200, status
      assert_equal "text/event-stream", headers["content-type"]
      assert_respond_to body, :call, "a listen body is the Rack 3 streaming shape"

      sink = FakeStream.new
      body.call(sink)
      assert_match(/notifications\/subscriptions\/acknowledged/, sink.frames.join)
    ensure
      app.close
    end
  end

  test "allowed_hosts admits the proxy Host that is refused without it" do
    request = { jsonrpc: "2.0", id: 3, method: "initialize",
                params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "0" } } }

    refused = OKF::MCP.app([ fixture("knowledge") ], engine: OKF::MCP::MemoryBackend.new)
    status, = refused.call(env_for(request, host: "mcp.example.com"))
    assert_equal 403, status, "a foreign Host is refused by default"

    admitted = OKF::MCP.app([ fixture("knowledge") ], engine: OKF::MCP::MemoryBackend.new,
      allowed_hosts: [ "mcp.example.com" ])
    status, _headers, body = admitted.call(env_for(request, host: "mcp.example.com"))
    assert_equal 200, status
    assert_equal "okf", JSON.parse(join(body)).dig("result", "serverInfo", "name")
  end

  # What the SDK writes SSE frames to, recorded instead of sent.
  class FakeStream
    attr_reader :frames

    def initialize
      @frames = []
    end

    def write(data)
      @frames << data
    end

    def flush; end

    def close; end
  end

  private

  # The env a Rack server hands the transport for one JSON POST — the same
  # keys the WEBrick bridge's env_for builds.
  def env_for(payload, host: "127.0.0.1", headers: {})
    body = JSON.generate(payload)
    {
      "REQUEST_METHOD" => "POST",
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "SERVER_NAME" => host,
      "SERVER_PORT" => "80",
      "rack.url_scheme" => "http",
      "rack.input" => StringIO.new(body),
      "rack.errors" => $stderr,
      "CONTENT_TYPE" => "application/json",
      "CONTENT_LENGTH" => body.bytesize.to_s,
      "HTTP_HOST" => host,
      "HTTP_ACCEPT" => "application/json, text/event-stream"
    }.merge(headers)
  end

  def tool_env(id:, name:, arguments: {})
    env_for({ jsonrpc: "2.0", id: id, method: "tools/call",
              params: { name: name, arguments: arguments } })
  end

  def join(body)
    return body if body.is_a?(String)

    buffer = String.new
    body.each { |chunk| buffer << chunk }
    buffer
  end
end
