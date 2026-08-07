# frozen_string_literal: true

require_relative "mcp_integration_case"

# Concepts as MCP resources — the affordance no tool call provides: a host can
# *attach* a concept to context without the model deciding to fetch it.
#
# The shape is one static resource per served bundle (derivable from the
# registry at boot, no bundle read) plus a template covering every concept
# (resolved live, through the same residency layer read_concept uses). The
# server used to declare a resources capability and serve nothing.
class ResourcesTest < MCPIntegrationCase
  test "every served bundle is listed as a resource" do
    server = mcp_server(fixture("knowledge"))
    resources = rpc(server, "resources/list").dig("result", "resources")

    assert_equal 1, resources.length
    row = resources.first
    assert_equal "okf://knowledge", row["uri"]
    assert_equal "knowledge", row["name"]
    assert_equal "text/markdown", row["mimeType"]
  end

  test "the concept template is published for discovery" do
    server = mcp_server(fixture("knowledge"))
    templates = rpc(server, "resources/templates/list").dig("result", "resourceTemplates")

    assert_equal 1, templates.length
    assert_equal "okf://{bundle}/{id}", templates.first["uriTemplate"]
    assert_equal "text/markdown", templates.first["mimeType"]
  end

  test "reading a bundle resource serves its root index verbatim" do
    server = mcp_server(fixture("knowledge"))
    contents = rpc(server, "resources/read", uri: "okf://knowledge").dig("result", "contents")

    assert_equal 1, contents.length
    assert_equal "okf://knowledge", contents.first["uri"]
    assert_equal read_utf8(File.join(fixture("knowledge"), "index.md")), contents.first["text"]
  end

  # The case a naive `okf://{bundle}/{id}` regex cannot serve: the SDK's
  # template matcher binds `{id}` to `[^/]+`, and every OKF id below the root
  # carries a slash. Hence the custom read handler — the template is published
  # for discovery, but the parsing is ours.
  test "a concept id containing a slash resolves" do
    server = mcp_server(fixture("knowledge"))
    contents = rpc(server, "resources/read", uri: "okf://knowledge/services/billing").dig("result", "contents")

    assert_equal "okf://knowledge/services/billing", contents.first["uri"]
    assert_equal read_utf8(File.join(fixture("knowledge"), "services", "billing.md")), contents.first["text"]
  end

  test "a resource read and read_concept return the same bytes" do
    server = mcp_server(fixture("knowledge"))
    via_resource = rpc(server, "resources/read", uri: "okf://knowledge/decisions/ledger").dig("result", "contents", 0, "text")
    via_tool = call_tool(server, "read_concept", bundle: "knowledge", id: "decisions/ledger").text

    assert_equal via_tool, via_resource
  end

  test "an unknown concept is an error naming what was asked for" do
    server = mcp_server(fixture("knowledge"))
    response = rpc(server, "resources/read", uri: "okf://knowledge/nope")

    assert response["error"], "expected a protocol error, got #{response.inspect}"
    assert_match(/nope/, JSON.generate(response["error"]))
  end

  # The containment rule the argv allowlist exists for, restated on a surface
  # that takes a URI instead of a slug argument: a URI is not a path, and no
  # resource read may reach a bundle argv did not name.
  test "a URI naming an unserved bundle is refused" do
    server = mcp_server(fixture("knowledge"))
    response = rpc(server, "resources/read", uri: "okf://other/secret")

    assert response["error"]
    # The kernel's own sentence, not a flattened "Invalid params".
    assert_match(/unknown bundle "other" — known: knowledge/, response.dig("error", "message"))
    assert_equal "okf://other/secret", response.dig("error", "data", "uri")
  end

  test "a malformed URI is refused rather than guessed at" do
    server = mcp_server(fixture("knowledge"))
    [ "https://knowledge/x", "okf:/knowledge", "okf://" ].each do |uri|
      response = rpc(server, "resources/read", uri: uri)
      assert response["error"], "#{uri} was not refused"
    end
  end

  # Listed implies readable — until the file moves under it. Bodies are read
  # live, which is the point, so the window between a listing and a read is
  # real and has to answer with a refusal rather than an errno.
  test "a root index deleted after the listing is a not-found, not a crash" do
    dir = scratch_bundle("vanishing")
    File.write(File.join(dir, "index.md"), "---\ntype: Index\ntitle: Vanishing\n---\n\nHere.\n")
    server = mcp_server(dir)
    assert_equal [ "okf://vanishing" ], rpc(server, "resources/list").dig("result", "resources").map { |r| r["uri"] }

    File.delete(File.join(dir, "index.md"))
    response = rpc(server, "resources/read", uri: "okf://vanishing")

    assert response["error"], "expected a refusal, got #{response.inspect}"
    assert_match(/okf:\/\/vanishing/, response.dig("error", "message"))
  end

  # One unreadable bundle must not cost the listing every other bundle.
  test "a bundle whose root cannot be stat'd is skipped, not fatal" do
    server = nil
    File.stub(:file?, ->(path) { raise Errno::ENAMETOOLONG, path }) do
      registry = OKF::MCP::Registry.from_argv([ fixture("knowledge") ])
      server = OKF::MCP::Server.build(registry, engine: OKF::MCP::MemoryBackend.new)
      handshake(server)
      assert_empty rpc(server, "resources/list").dig("result", "resources")
    end
  end

  test "several served bundles each get their own resource" do
    server = mcp_server(fixture("knowledge"), fixture("notes"))
    uris = rpc(server, "resources/list").dig("result", "resources").map { |row| row["uri"] }

    assert_equal %w[okf://knowledge okf://notes], uris
  end
end
