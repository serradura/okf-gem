# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf graph` end-to-end — node/edge counts, link resolution, best-effort parsing,
# and the pure (render-free) JSON graph model.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIGraphTest < CLIIntegrationCase
    test "prints node and edge counts for a conformant bundle" do
      status = nil
      assert_output(/3 concepts, 6 links/, "") { status = start_cli("graph", fixture("conformant")) }
      assert_equal 0, status
    end

    test "edge-cases resolve inline, titled, anchored, and reference-style links" do
      status = nil
      assert_output(/4 concepts, 4 links/, "") { status = start_cli("graph", fixture("edge-cases")) }
      assert_equal 0, status
    end

    test "is best-effort — malformed files are skipped (stderr) not fatal (issue #2)" do
      status = nil
      assert_output(/3 concepts, 0 links/, /skipped 2 file\(s\) with invalid frontmatter/) do
        status = start_cli("graph", fixture("malformed"))
      end
      assert_equal 0, status
    end

    test "an empty bundle yields an empty graph" do
      status = nil
      assert_output(/0 concepts, 0 links/, "") { status = start_cli("graph", fixture("empty")) }
      assert_equal 0, status
    end

    test "--json emits the pure graph model — nodes carry knowledge, no render fields" do
      result = okf("graph", fixture("minimal"), "--json")
      data = JSON.parse(result.out)

      node = data.fetch("nodes").first
      assert_equal %w[body description id tags title type], node.keys.sort
      refute node.key?("sz"),    "sz is a render concern and must not appear in the graph model"
      refute node.key?("group"), "group is not part of the graph model"
      assert_equal [], data.fetch("edges")
    end

    test "--minimal ships lean nodes plus type and tag indexes" do
      result = okf("graph", fixture("conformant"), "--json", "--minimal")
      data = JSON.parse(result.out)

      assert_equal %w[id title], data.fetch("nodes").first.keys.sort
      assert data.key?("types")
      assert data.key?("tags")
    end

    test "--no-body keeps metadata but drops the body" do
      result = okf("graph", fixture("minimal"), "--json", "--no-body")
      node = JSON.parse(result.out).fetch("nodes").first

      assert_equal %w[description id tags title type], node.keys.sort
    end
  end
end
