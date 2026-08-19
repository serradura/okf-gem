# frozen_string_literal: true

require_relative "mcp_integration_case"

# Argument completion for the resource template. Bundle slugs and concept ids
# are closed vocabularies a host can offer instead of making somebody type
# them — and read_concept's own description ("ids are exact: take them from
# search, index, or catalog") was a workaround for their absence.
class CompletionsTest < MCPIntegrationCase
  TEMPLATE = "okf://{bundle}/{id}"

  test "the bundle argument completes to the served slugs" do
    server = mcp_server(fixture("knowledge"), fixture("notes"))
    assert_equal %w[knowledge notes], complete(server, "bundle", "")
  end

  test "a partial value narrows by prefix" do
    server = mcp_server(fixture("knowledge"), fixture("notes"))
    assert_equal %w[knowledge], complete(server, "bundle", "kn")
    assert_equal [], complete(server, "bundle", "zz")
  end

  test "prefix matching folds case, as every other name comparison here does" do
    server = mcp_server(fixture("knowledge"))
    assert_equal %w[knowledge], complete(server, "bundle", "KNOW")
  end

  test "the id argument completes to the concept ids of the bundle in context" do
    server = mcp_server(fixture("knowledge"))
    ids = call_tool!(server, "catalog", bundle: "knowledge")["concepts"].map { |row| row["id"] }.sort

    assert_equal ids, complete(server, "id", "", bundle: "knowledge")
  end

  test "an id prefix narrows within the bundle" do
    server = mcp_server(fixture("knowledge"))
    assert_equal %w[services/billing services/search], complete(server, "id", "services/", bundle: "knowledge")
  end

  # Without a bundle there is no set to complete from, and guessing across
  # every served bundle would answer about one the caller never named.
  test "an id with no bundle in context completes to nothing" do
    server = mcp_server(fixture("knowledge"))
    assert_equal [], complete(server, "id", "")
  end

  # The containment rule again, on the one surface that takes a free-form
  # value: completion must never confirm the existence of a bundle argv did
  # not serve, let alone list its concepts.
  test "an unserved bundle in context completes to nothing, not an error" do
    server = mcp_server(fixture("knowledge"))
    assert_equal [], complete(server, "id", "", bundle: "notes")
  end

  test "an unknown argument name completes to nothing" do
    server = mcp_server(fixture("knowledge"))
    assert_equal [], complete(server, "nonsense", "")
  end

  test "our prompts take no arguments, so a prompt ref completes to nothing" do
    server = mcp_server(fixture("knowledge"))
    response = rpc(server, "completion/complete",
      ref: { type: "ref/prompt", name: "okf-search" }, argument: { name: "anything", value: "" })

    assert_equal [], response.dig("result", "completion", "values")
  end

  test "completions is declared, now that something answers" do
    registry = OKF::MCP::Registry.from_argv([ fixture("knowledge") ])
    server = OKF::MCP::Server.build(registry, engine: OKF::MCP::MemoryBackend.new)
    assert_includes handshake(server)["capabilities"].keys, "completions"
  end

  private

  def complete(server, name, value, **context_arguments)
    params = {
      ref: { type: "ref/resource", uri: TEMPLATE },
      argument: { name: name, value: value }
    }
    params[:context] = { arguments: context_arguments } unless context_arguments.empty?
    rpc(server, "completion/complete", params).dig("result", "completion", "values")
  end
end
