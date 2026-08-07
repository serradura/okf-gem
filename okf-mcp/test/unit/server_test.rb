# frozen_string_literal: true

require "test_helper"
require "okf/mcp/server"

# The tool wrapper's own guarantees, driven below the protocol so the paths a
# schema normally intercepts stay provable.
class ServerTest < OKF::TestCase
  FIXTURES = File.expand_path("../integration/fixtures", __dir__)

  setup do
    @registry = OKF::MCP::Registry.from_argv([ File.join(FIXTURES, "knowledge") ])
    @tools = OKF::MCP::Server.tools_for(
      OKF::MCP::Server::Context.new(@registry, OKF::MCP::MemoryBackend.new, OKF::MCP::MemoryBackend.new)
    )
  end

  test "every tool closes its schema against unknown arguments" do
    @tools.each do |tool|
      assert_equal false, tool.input_schema.to_h[:additionalProperties],
        "#{tool.name_value} accepts unknown arguments"
    end
  end

  # Calling the tool class directly is what a host with
  # `validate_tool_call_arguments` turned off does: no schema stands between
  # the arguments and the block. The rescue is what keeps that from surfacing
  # as an opaque JSON-RPC internal error instead of something a model can read.
  test "an unknown argument is a tool error even with schema validation bypassed" do
    dirs = @tools.find { |tool| tool.name_value == "dirs" }
    response = dirs.call(bundle: "knowledge", sort: "title")

    assert response.error?
    assert_match(/unknown keyword: :sort/, response.content.first[:text])
    assert_match(/tool dirs/, response.content.first[:text])
  end

  test "a domain refusal keeps the kernel's own sentence" do
    dirs = @tools.find { |tool| tool.name_value == "dirs" }
    response = dirs.call(bundle: "nope")

    assert response.error?
    assert_match(/unknown bundle "nope" — known: knowledge/, response.content.first[:text])
  end

  # The per-request work — the fingerprint memo and the residency prune — hangs
  # off both public entry points. Neither transport calls `handle` (they go
  # through `handle_json`), so no integration test reaches it; an embedding app
  # that hands the server a parsed Hash does, and skipping the wrapper there
  # would leave its residency unbounded.
  test "the request seam wraps `handle`, not only `handle_json`" do
    memory = OKF::MCP::MemoryBackend.new
    wrapped = 0
    memory.singleton_class.prepend(Module.new do
      define_method(:during_request) { |&block| wrapped += 1; super(&block) }
    end)
    server = OKF::MCP::Server.build(@registry, engine: memory)

    # Braced, so the hash is the positional request rather than keywords.
    server.handle({ jsonrpc: "2.0", id: 1, method: "initialize",
                    params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "0" } } })
    assert_equal 1, wrapped

    server.handle_json(JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/list", params: {}))
    assert_equal 2, wrapped
  end
end
