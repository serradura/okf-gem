# frozen_string_literal: true

require_relative "mcp_integration_case"

# What the server says it can do, checked against what it actually answers.
#
# The SDK's default declares every capability it knows how to route — tools,
# prompts, resources and logging, each with listChanged. Inheriting that made
# the handshake advertise a resources capability while `resources/list`
# returned `[]`, and a logging one nothing ever emitted through. Honest
# annotations are a rule this server already keeps for tools (`readOnlyHint`);
# these tests keep it for the handshake.
class CapabilitiesTest < MCPIntegrationCase
  test "the declared capabilities are exactly what is served" do
    assert_equal({ "tools" => {}, "prompts" => {}, "resources" => {}, "completions" => {} }, declared_capabilities)
  end

  # The wire-level half of the "ten read-only tools" promise. Hosts gate
  # auto-approval on `readOnlyHint`, so one tool shipped without it demotes
  # the whole server to write-suspect in read-only contexts — and the
  # assertion that pinned this lived in a prompts test that was deleted with
  # the playbooks it checked. It lives here now, with the other honesty rules.
  test "every tool on the wire declares itself read-only" do
    server = mcp_server(fixture("knowledge"))
    tools = rpc(server, "tools/list").dig("result", "tools")
    assert_equal 10, tools.length
    tools.each do |tool|
      assert_equal true, tool.dig("annotations", "readOnlyHint"), "#{tool["name"]} does not declare readOnlyHint"
      assert_equal false, tool.dig("annotations", "destructiveHint"), "#{tool["name"]} does not disclaim destruction"
    end
  end

  # The general rule, stated so a regression of the same class fails here
  # rather than in a host: nothing may be declared that answers empty.
  test "every declared capability answers with something" do
    server = mcp_server(fixture("knowledge"))

    listings = {
      "tools" => -> { rpc(server, "tools/list").dig("result", "tools") },
      "prompts" => -> { rpc(server, "prompts/list").dig("result", "prompts") },
      "resources" => -> { rpc(server, "resources/list").dig("result", "resources") },
      # Completions has no listing, so the equivalent question is whether the
      # one thing it exists to complete actually comes back with values.
      "completions" => lambda {
        rpc(server, "completion/complete",
          ref: { type: "ref/resource", uri: OKF::MCP::Resources::TEMPLATE },
          argument: { name: "bundle", value: "" }).dig("result", "completion", "values")
      }
    }
    declared_capabilities.each_key do |name|
      list = listings.fetch(name) { flunk("declared #{name}, which no test knows how to list") }.call
      refute_empty list, "#{name} is declared but answers empty"
    end
  end

  test "logging is not declared, because nothing ever emits a log message" do
    refute_includes declared_capabilities.keys, "logging"
  end

  # listChanged is a promise to send a notification. This server's lists are
  # fixed for the life of a process, so claiming it would leave a host waiting.
  test "no capability claims listChanged or subscribe" do
    declared_capabilities.each do |name, config|
      assert_empty config, "#{name} claims #{config.keys.join(", ")}, which nothing implements"
    end
  end

  private

  # Built and handshaken here rather than through #mcp_server, which discards
  # the initialize result — and the SDK refuses a second initialize on a
  # session that already has one.
  def declared_capabilities
    registry = OKF::MCP::Registry.from_argv([ fixture("knowledge") ])
    server = OKF::MCP::Server.build(registry, engine: OKF::MCP::MemoryBackend.new)
    handshake(server)["capabilities"]
  end
end
