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
  test "the okf floor moves with okf's release — 1.13.0 lacks the surfaces this shell reads" do
    # The gemspec carries this as a RELEASE OBLIGATION prose note; this is the
    # tripwire that makes it mechanical. The floor cannot move before okf's
    # own version does (the monorepo resolves against the path-sourced okf),
    # so: the moment okf releases past 1.13.0, this test goes red until the
    # floor excludes 1.13.0 — against which a status filter raises NameError
    # and a trust filter silently matches nothing.
    gemspec = Gem::Specification.load(File.expand_path("../../okf-mcp.gemspec", __dir__))
    floor = gemspec.dependencies.find { |dep| dep.name == "okf" }.requirement

    if Gem::Version.new(OKF::VERSION) > Gem::Version.new("1.13.0")
      refute floor.satisfied_by?(Gem::Version.new("1.13.0")),
        "okf moved past 1.13.0 — the RELEASE OBLIGATION in okf-mcp.gemspec is due"
    else
      assert floor.satisfied_by?(Gem::Version.new(OKF::VERSION)),
        "the floor must keep resolving against the monorepo's own okf"
    end
  end
end
