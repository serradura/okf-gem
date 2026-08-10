# frozen_string_literal: true

require_relative "mcp_integration_case"

# Adversarial containment probes (review of PR #26). The security model: a
# tool's `bundle` arg is a registry slug, `id` resolves through the bundle's
# paths_by_id map, and Path.join_under! guards the root. These probes assert
# that no request can surface file content from outside a served bundle root.
#
# The lexical (id / URI) probes all hold. The SYMLINK probes below currently
# FAIL — Path.join_under! is a lexical check (File.expand_path, not realpath),
# so a symlink whose *name* is in-root but whose *target* is outside is
# followed. Left in as the red repro for that finding.
class ContainmentProbeTest < MCPIntegrationCase
  def with_secret
    secret = File.join(@out_dir, "SECRET.txt")
    File.write(secret, "root:x:0:0:TOP SECRET — must never appear in a result\n")
    yield secret
  end

  # ── lexical containment: these hold ──────────────────────────────────────

  test "read_concept — traversal ids never escape the root" do
    with_secret do
      server = mcp_server(fixture("knowledge"))
      [ "../../etc/passwd", "..%2F..%2Fetc/passwd", "/etc/passwd",
        "../../../#{File.basename(@out_dir)}/SECRET.txt", "#{@out_dir}/SECRET.txt",
        "services/../../../etc/passwd", "services/billing/../../../../etc/hosts" ].each do |id|
        result = call_tool(server, "read_concept", bundle: "knowledge", id: id)
        assert result.error?, "expected refusal for id #{id.inspect}, got: #{result.text[0, 120]}"
        refute_match(/root:x:0:0|TOP SECRET/, result.text, "LEAK via id #{id.inspect}")
      end
    end
  end

  test "read_concept — an id living only in an UNSERVED bundle is not found" do
    server = mcp_server(fixture("knowledge"))
    result = call_tool(server, "read_concept", bundle: "knowledge", id: "glossary")
    assert result.error?, "unserved-bundle id resolved: #{result.text[0, 120]}"
  end

  test "resources/read — traversal URIs never escape the served root" do
    with_secret do
      server = mcp_server(fixture("knowledge"))
      [ "okf://knowledge/../../etc/passwd",
        "okf://knowledge/../#{File.basename(@out_dir)}/SECRET.txt",
        "okf://knowledge/services/../../../../etc/passwd",
        "okf://../#{File.basename(@out_dir)}/SECRET.txt",
        "okf://knowledge/..%2F..%2Fetc%2Fpasswd" ].each do |uri|
        response = rpc(server, "resources/read", uri: uri)
        payload = JSON.generate(response)
        assert response["error"], "expected refusal for uri #{uri.inspect}, got: #{payload[0, 160]}"
        refute_match(/root:x:0:0|TOP SECRET/, payload, "LEAK via uri #{uri.inspect}")
      end
    end
  end

  test "resources/read — a URI naming an unserved bundle is refused" do
    server = mcp_server(fixture("knowledge"))
    response = rpc(server, "resources/read", uri: "okf://notes/glossary")
    assert response["error"], "unserved bundle served via resource URI"
  end

  test "completion/complete — cannot enumerate an unserved bundle" do
    server = mcp_server(fixture("knowledge"))
    names = rpc(server, "completion/complete",
      ref: { type: "ref/resource", uri: OKF::MCP::Resources::TEMPLATE },
      argument: { name: "bundle", value: "" }).dig("result", "completion", "values")
    assert_equal [ "knowledge" ], names, "completion leaked non-served bundle slugs"

    ids = rpc(server, "completion/complete",
      ref: { type: "ref/resource", uri: OKF::MCP::Resources::TEMPLATE },
      argument: { name: "id", value: "" },
      context: { arguments: { bundle: "notes" } }).dig("result", "completion", "values")
    assert_empty ids, "completion enumerated ids of an unserved bundle: #{ids.inspect}"
  end

  # ── symlink containment: these FAIL — the finding ────────────────────────

  # A symlinked concept file (valid frontmatter) whose target is outside the
  # root. glob finds it, it parses as a concept, join_under! passes on the
  # in-root name, and File.read follows the link.
  test "read_concept — a symlink to an outside concept is not followed" do
    outside = File.join(@out_dir, "exfil.md")
    File.write(outside, "---\ntype: Note\ntitle: Exfil\n---\n\nroot:x:0:0 TOP SECRET body\n")
    dir = scratch_bundle("linky")
    File.symlink(outside, File.join(dir, "escape.md"))
    server = mcp_server(dir)

    result = call_tool(server, "read_concept", bundle: "linky", id: "escape")
    refute_match(/TOP SECRET/, result.text, "LEAK: read_concept followed a symlink out of the root")
  end

  # The worst variant: a symlinked index.md is read with a raw File.read (no
  # frontmatter needed), so ANY outside file is served verbatim, listed, and
  # readable via okf://<slug>.
  test "resources/read — a symlinked root index does not export an arbitrary outside file" do
    outside = File.join(@out_dir, "passwd")
    File.write(outside, "root:x:0:0:arbitrary non-OKF file:/root:/bin/sh\n")
    dir = File.join(@out_dir, "linkidx")
    FileUtils.mkdir_p(dir)
    File.symlink(outside, File.join(dir, "index.md"))
    server = mcp_server(dir)

    response = rpc(server, "resources/read", uri: "okf://linkidx")
    refute_match(/root:x:0:0/, JSON.generate(response), "LEAK: symlinked index.md served an arbitrary outside file")
  end
end
