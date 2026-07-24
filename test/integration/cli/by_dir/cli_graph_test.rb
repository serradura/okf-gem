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
      assert_output(/3 concepts, 0 links/, /skipped 2 unusable file\(s\)/) do
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

    test "--hubs ranks concepts by inbound links, each with the top-level dirs the links come from" do
      result = okf("graph", fixture("shapely"), "--hubs")

      assert_equal 0, result.status
      assert_match(/\AHubs — .*shapely \(2 of 4 concepts with inbound links\)\n\n/, result.out)
      assert_match(%r{^  core/status\s+×3   flows 2, billing 1$}, result.out)
      assert_match(%r{^  flows/activate\s+×1   flows 1$}, result.out)
      assert_operator result.out.index("core/status"), :<, result.out.index("flows/activate"), "ranked by inbound degree"
    end

    test "--hubs --json emits the ranked rows with the per-source-top-dir breakdown" do
      data = json(okf("graph", fixture("shapely"), "--hubs", "--json"))

      assert_equal 2, data.fetch("count")
      assert_equal [ { "id" => "core/status", "top_dir" => "core", "inbound" => 3, "by_top_dir" => { "flows" => 2, "billing" => 1 } },
                     { "id" => "flows/activate", "top_dir" => "flows", "inbound" => 1, "by_top_dir" => { "flows" => 1 } } ],
        data.fetch("hubs")
    end

    test "--hubs labels a root-level source top-level dir (root), like every grouped view" do
      data = json(okf("graph", fixture("rooted"), "--hubs", "--json"))

      gateway = data.fetch("hubs").find { |row| row.fetch("id") == "services/gateway" }
      assert_equal({ "(root)" => 1 }, gateway.fetch("by_top_dir"))
    end

    test "--hubs on a linkless bundle reports zero hubs, not an error" do
      result = okf("graph", fixture("minimal"), "--hubs")

      assert_equal 0, result.status
      assert_match(/0 of 1 concept with inbound links/, result.out)
      assert_equal [], json(okf("graph", fixture("minimal"), "--hubs", "--json")).fetch("hubs")
    end

    # ── --traffic: directories, and the traffic between them ──

    test "--traffic collapses concepts into their dirs and the links into weighted arcs" do
      result = okf("graph", fixture("shapely"), "--traffic")

      assert_equal 0, result.status
      assert_match(/\ATraffic — .*shapely \(4 dirs, 2 arcs at weight 1 or more\)\n/, result.out)
      assert_match(/^  Dir      Concepts  Internal   Out    In  Cohesion$/, result.out)
      assert_match(/^    flows   → core  ×2$/, result.out)
      assert_match(/^    billing → core  ×1$/, result.out)
      assert_operator result.out.index("flows   → core"), :<, result.out.index("billing → core"), "arcs rank by weight"
    end

    test "the cohesion column is a dir's own traffic over its total, leading with the lowest" do
      out = okf("graph", fixture("shapely"), "--traffic").out

      # flows holds 2 concepts with 1 link between them and 2 leaving: 1/3.
      assert_match(/^  flows           2         1     2     0       33%$/, out)
      # core is pure sink — 3 in, nothing internal.
      assert_match(/^  core            1         0     0     3        0%$/, out)
      assert_operator out.index("  core "), :<, out.index("  flows "), "the dirs with a case to answer come first"
    end

    test "a dir with no traffic at all reports no ratio rather than a 0% it did not earn" do
      out = okf("graph", fixture("shapely"), "--traffic").out

      assert_match(/^  \(root\)          0         0     0     0         —$/, out)
      assert_operator out.index("(root)"), :>, out.index("  flows "), "and sorts last, having nothing to answer for"
    end

    test "cohesion is measured over every arc, never the drawn ones — the cut must not move it" do
      loose = okf("graph", fixture("shapely"), "--traffic", "--cut", "1").out
      tight = okf("graph", fixture("shapely"), "--traffic", "--cut", "9").out

      assert_match(/^  flows           2         1     2     0       33%$/, loose)
      assert_match(/^  flows           2         1     2     0       33%$/, tight, "a tighter cut drew fewer arcs, it did not unlink the bundle")
    end

    test "--cut is fitted to the bundle when nobody passes one, and says which it was" do
      fitted = json(okf("graph", fixture("shapely"), "--traffic", "--json"))
      given = json(okf("graph", fixture("shapely"), "--traffic", "--cut", "2", "--json"))

      assert_equal true, fitted.fetch("fitted")
      assert_equal 1, fitted.fetch("cut"), "four dirs and two arcs sit under the floor, so nothing is cut"
      assert_equal false, given.fetch("fitted")
      assert_equal 2, given.fetch("cut")
    end

    test "--traffic cuts the arcs by weight, and says so when the cut empties them" do
      assert_match(/1 of 2 arcs at weight 2 or more/, okf("graph", fixture("shapely"), "--traffic", "--cut", "2").out)

      tight = okf("graph", fixture("shapely"), "--traffic", "--cut", "9")

      assert_equal 0, tight.status
      assert_match(/0 of 2 arcs at weight 9 or more/, tight.out)
      assert_match(/^    \(none at this cut\)$/, tight.out, "an empty arc list still prints, or the cut reads as the bundle")
      assert_match(/^  flows /, tight.out, "the dirs stay — only the arcs were cut")
    end

    test "--traffic --json carries the bundle head, the cut, the dirs and the untaken total" do
      data = json(okf("graph", fixture("shapely"), "--traffic", "--json", "--cut", "1"))

      assert_equal 1, data.fetch("cut")
      assert_equal 2, data.fetch("total_arcs")
      assert_equal [ { "source" => "flows", "target" => "core", "weight" => 2 },
                     { "source" => "billing", "target" => "core", "weight" => 1 } ], data.fetch("arcs")
      assert_equal({ "dir" => "flows", "parent" => ".", "count" => 2, "subtree" => 2, "internal" => 1,
                     "out" => 2, "in" => 0, "cohesion" => 33 },
        data.fetch("dirs").find { |row| row["dir"] == "flows" })
    end

    test "--traffic --json reports a traffic-free dir's cohesion as null, not as zero" do
      root = json(okf("graph", fixture("shapely"), "--traffic", "--json")).fetch("dirs").find { |row| row["dir"] == "." }

      assert_nil root.fetch("cohesion")
      assert_equal 0, root.fetch("count")
    end

    test "--traffic composes with --pretty, and --minimal/--no-body change nothing it reads" do
      pretty = okf("graph", fixture("shapely"), "--traffic", "--pretty")

      assert_equal json(okf("graph", fixture("shapely"), "--traffic", "--json")), JSON.parse(pretty.out)
      assert_equal okf("graph", fixture("shapely"), "--traffic").out,
        okf("graph", fixture("shapely"), "--traffic", "--minimal", "--no-body").out
    end

    test "--traffic outranks --hubs when both are asked for" do
      out = okf("graph", fixture("shapely"), "--traffic", "--hubs").out

      assert_match(/\ATraffic —/, out)
      refute_match(/\AHubs —/, out)
    end

    test "--traffic rejects a cut below 1 (exit 2), printing nothing" do
      zero = okf("graph", fixture("shapely"), "--traffic", "--cut", "0")

      assert_equal 2, zero.status
      assert_equal "error: --cut must be 1 or more, got 0\n", zero.err
      assert_empty zero.out
    end

    test "--traffic takes no --mode: the three reductions became one" do
      result = okf("graph", fixture("shapely"), "--traffic", "--mode", "top")

      assert_equal 2, result.status
      assert_match(/invalid option: --mode/, result.err)
      assert_empty result.out
    end

    test "--traffic is best-effort and survives an empty bundle" do
      empty = okf("graph", fixture("empty"), "--traffic")
      assert_equal 0, empty.status
      assert_match(/\(0 dirs, 0 arcs at weight 1 or more\)/, empty.out)
      refute_match(/^  Dir /, empty.out, "no column header over an empty table")

      malformed = okf("graph", fixture("malformed"), "--traffic")
      assert_equal 0, malformed.status
      assert_match(/skipped 2 unusable file\(s\)/, malformed.err)
    end

    test "--hubs composes with --pretty, and --minimal/--no-body change nothing it reads" do
      pretty = okf("graph", fixture("shapely"), "--hubs", "--pretty")

      assert_equal json(okf("graph", fixture("shapely"), "--hubs", "--json")), JSON.parse(pretty.out)
      assert_equal okf("graph", fixture("shapely"), "--hubs").out,
        okf("graph", fixture("shapely"), "--hubs", "--minimal", "--no-body").out
    end
  end
end
