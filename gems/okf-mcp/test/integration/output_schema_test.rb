# frozen_string_literal: true

require_relative "mcp_integration_case"

# Structured output: every JSON-returning tool declares the shape it answers
# with, and emits `structuredContent` beside the text — so a host consumes a
# result without parsing a blob and guessing.
#
# The schemas are proven rather than asserted: these tests build the server
# with the SDK's result validation turned *on* and call every tool through
# every variant it has. A schema that drifts from its payload fails here.
# Production leaves validation off on purpose — a schema bug should not turn a
# working tool into a runtime error, and this suite is where it gets caught.
class OutputSchemaTest < MCPIntegrationCase
  # Every tool, with each variant that changes the payload's shape.
  VARIANTS = [
    [ "list_bundles", {} ],
    [ "dirs", { bundle: "knowledge" } ],
    [ "dirs", { bundle: "knowledge", dir: "services", depth: 1 } ],
    [ "index", { bundle: "knowledge" } ],
    [ "index", { bundle: "knowledge", bodies: true, listing: true, depth: 3 } ],
    [ "search", { terms: %w[billing] } ],
    [ "search", { terms: %w[billing], engine: "index", limit: 5, in: %w[title] } ],
    [ "search", { terms: %w[a], bundle: "scrappy" } ],
    [ "catalog", { bundle: "knowledge" } ],
    [ "catalog", { bundle: "knowledge", limit: 1, offset: 1, fields: %w[id] } ],
    [ "catalog", { bundle: "scrappy" } ],
    [ "log", { bundle: "knowledge" } ],
    [ "log", { bundle: "knowledge", limit: 1 } ],
    [ "validate", { bundle: "knowledge" } ],
    [ "validate", { bundle: "scrappy" } ],
    [ "lint", { bundle: "knowledge" } ],
    [ "lint", { bundle: "knowledge", stale_after: "1d" } ],
    [ "lint", { bundle: "knowledge", group: "folder" } ],
    [ "graph", { bundle: "knowledge" } ],
    [ "graph", { bundle: "knowledge", view: "hubs" } ],
    [ "graph", { bundle: "knowledge", view: "traffic" } ],
    [ "graph", { bundle: "scrappy" } ],
    [ "graph", { bundle: "knowledge", view: "traffic", cut: 1 } ],
    [ "references", { bundle: "knowledge" } ],
    [ "references", { bundle: "referenced" } ],
    [ "tags", { bundle: "knowledge" } ],
    [ "tags", { bundle: "knowledge", by: "dir" } ],
    [ "tags", { bundle: "knowledge", by: "type" } ],
    [ "types", { bundle: "knowledge" } ],
    [ "stats", { bundle: "knowledge" } ],
    [ "catalog", { bundle: "knowledge", except: %w[description tags] } ],
    [ "search", { terms: %w[billing], fields: %w[id score] } ],
    [ "lint", { bundle: "knowledge", today: "2026-01-01" } ]
  ].freeze

  test "every tool but read_concept declares an output schema" do
    server = mcp_server(fixture("knowledge"))
    tools = rpc(server, "tools/list").dig("result", "tools")

    with_schema, without = tools.partition { |tool| tool.key?("outputSchema") }
    assert_equal %w[read_concept], without.map { |tool| tool["name"] },
      "read_concept returns markdown, so it is the only one with no shape to declare"
    with_schema.each do |tool|
      assert_equal "object", tool.dig("outputSchema", "type"), "#{tool["name"]} declares a non-object root"
      refute_empty tool.dig("outputSchema", "properties"), "#{tool["name"]} declares an empty shape"
    end
  end

  # `skipped` appears only when "*" forgave a vanished bundle, so the happy
  # VARIANTS never emit it — and a declared schema that omits a real field is
  # exactly the drift this suite exists to catch.
  test "a search that skipped a vanished bundle still validates" do
    goner = File.join(@out_dir, "goner")
    FileUtils.mkdir_p(goner)
    File.write(File.join(goner, "note.md"), "---\ntype: Note\ntitle: N\n---\n\nbody\n")
    registry = OKF::MCP::Registry.from_argv([ fixture("knowledge"), goner ])
    server = OKF::MCP::Server.build(
      registry,
      engine: OKF::MCP::MemoryBackend.new,
      configuration: ::MCP::Configuration.new(validate_tool_call_results: true)
    )
    handshake(server)
    FileUtils.rm_rf(goner)

    result = call_tool(server, "search", terms: %w[billing], bundle: "*")

    refute result.error?, "the skipped bundle broke result validation: #{result.text}"
    assert result.data.key?("skipped"), "the vanished bundle must be confessed"
  end

  test "every payload validates against the schema its tool declares" do
    server = validating_server
    VARIANTS.each do |name, args|
      result = call_tool(server, name, args)
      refute result.error?, "#{name}#{args.inspect} errored: #{result.text}"
    end
  end

  test "structuredContent carries the same object the text does" do
    server = mcp_server(fixture("knowledge"), fixture("scrappy"), fixture("referenced"))
    VARIANTS.each do |name, args|
      response = rpc(server, "tools/call", name: name, arguments: args)
      result = response.fetch("result")
      structured = result["structuredContent"]
      refute_nil structured, "#{name}#{args.inspect} emitted no structuredContent"
      assert_equal JSON.parse(result.dig("content", 0, "text")), structured
    end
  end

  test "read_concept stays text: markdown is not an object" do
    server = mcp_server(fixture("knowledge"))
    result = rpc(server, "tools/call", name: "read_concept",
      arguments: { bundle: "knowledge", id: "services/billing" }).fetch("result")

    assert_nil result["structuredContent"]
    assert_match(/\A---\n/, result.dig("content", 0, "text"))
  end

  # A refusal carries no payload, so it must not be validated against one —
  # the SDK skips isError results, and this pins that we rely on it.
  test "a refusal is still a plain tool error under result validation" do
    result = call_tool(validating_server, "dirs", bundle: "nope")

    assert result.error?
    assert_match(/unknown bundle "nope"/, result.text)
  end

  private

  def validating_server
    registry = OKF::MCP::Registry.from_argv([ fixture("knowledge"), fixture("scrappy"), fixture("referenced") ])
    server = OKF::MCP::Server.build(
      registry,
      engine: OKF::MCP::MemoryBackend.new,
      configuration: ::MCP::Configuration.new(validate_tool_call_results: true)
    )
    handshake(server)
    server
  end
end
