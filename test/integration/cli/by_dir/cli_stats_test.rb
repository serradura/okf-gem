# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf stats` end-to-end — the bundle-level rollups (size, spread, connectedness)
# with the per-type and per-area breakdowns under them. The "how big is this, and
# what is it made of?" view; no filters, advisory read: exit 0.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIStatsTest < CLIIntegrationCase
    test "reports the rollups and both breakdowns (exit 0)" do
      result = okf("stats", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/^Stats — .*conformant$/, result.out)
      assert_match(/^  concepts       3$/, result.out)
      assert_match(/^  dirs           2$/, result.out)
      assert_match(/^  concept types  2$/, result.out)
      assert_match(/^  cross-links    6$/, result.out)
      assert_match(/^  distinct tags  2$/, result.out)
      assert_match(/^  By type\n    BigQuery Table    2\n    BigQuery Dataset  1$/, result.out)
      assert_match(/^  By dir\n    tables    2\n    datasets  1$/, result.out)
      refute_match(/By area/, result.out) # the human view speaks one word for grouping
    end

    test "the breakdowns order by count, the biggest slice first" do
      result = okf("stats", fixture("edge-cases"))

      assert_match(/^  By dir\n    \(root\)              3\n    deeply\/nested\/path  1$/, result.out)
      assert_equal [ ".", "deeply/nested/path" ], json(okf("stats", fixture("edge-cases"), "--json")).fetch("by_dir").keys
    end

    test "by_dir keeps the whole path where by_area only ever kept the first segment" do
      data = json(okf("stats", fixture("edge-cases"), "--json"))

      assert_equal({ "." => 3, "deeply/nested/path" => 1 }, data.fetch("by_dir"))
      assert_equal({ "(root)" => 3, "deeply" => 1 }, data.fetch("by_area"), "kept for the deprecation window")
      assert_equal 2, data.fetch("dirs")
    end

    test "--json emits the rollups under their machine keys" do
      data = json(okf("stats", fixture("conformant"), "--json"))

      assert_equal %w[areas bundle by_area by_dir by_type concept_types concepts cross_links dirs distinct_tags], data.keys.sort
      assert_equal 3, data.fetch("concepts")
      assert_equal 2, data.fetch("areas")
      assert_equal 2, data.fetch("concept_types") # `types` in the human view, `concept_types` here
      assert_equal 6, data.fetch("cross_links")
      assert_equal 2, data.fetch("distinct_tags")
      assert_equal({ "BigQuery Table" => 2, "BigQuery Dataset" => 1 }, data.fetch("by_type"))
      assert_equal({ "tables" => 2, "datasets" => 1 }, data.fetch("by_area"))
    end

    test "--pretty implies --json and indents it" do
      result = okf("stats", fixture("minimal"), "--pretty")

      assert_equal 1, JSON.parse(result.out).fetch("concepts") # still JSON, no --json needed
      assert_match(/^  "concepts": 1,$/, result.out)
      assert_match(/^  "by_type": \{\n    "Note": 1\n  \},$/, result.out)
      refute_match(/\n  "concepts"/, okf("stats", fixture("minimal"), "--json").out) # compact by default
    end

    test "the counts track the bundle: a one-concept bundle links nothing" do
      data = json(okf("stats", fixture("minimal"), "--json"))

      assert_equal 1, data.fetch("concepts")
      assert_equal 0, data.fetch("cross_links")
      assert_equal 0, data.fetch("distinct_tags")
      assert_equal({ "(root)" => 1 }, data.fetch("by_area"))
    end

    test "an empty bundle is all zeroes, with no breakdowns and no crash" do
      result = okf("stats", fixture("empty"))

      assert_equal 0, result.status
      assert_match(/^  concepts       0$/, result.out)
      assert_match(/^  dirs           0$/, result.out)
      assert_match(/^  concept types  0$/, result.out)
      assert_match(/^  cross-links    0$/, result.out)
      assert_match(/^  distinct tags  0$/, result.out)
      refute_match(/By type/, result.out) # an empty breakdown prints nothing, not an empty heading
      refute_match(/By dir/, result.out)

      data = json(okf("stats", fixture("empty"), "--json"))
      assert_equal 0, data.fetch("concepts")
      assert_equal({}, data.fetch("by_type"))
      assert_equal({}, data.fetch("by_dir"))
    end

    test "JSON names the bundle by its directory; a bundle named by path carries no slug" do
      data = json(okf("stats", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      refute data.key?("slug")
      assert_match(/^Stats — #{Regexp.escape(fixture("conformant"))}$/, okf("stats", fixture("conformant")).out)
    end

    test "usage errors exit 2: a missing directory, no directory at all, an unknown flag" do
      missing = okf("stats", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)

      bare = okf("stats")
      assert_equal 2, bare.status
      assert_match(/Usage: okf stats <dir\|@slug>/, bare.err)

      # stats rolls up the whole bundle — the read views' filters are not on offer
      filtered = okf("stats", fixture("conformant"), "--type", "BigQuery Table")
      assert_equal 2, filtered.status
      assert_match(/invalid option: --type/, filtered.err)
      assert_equal "", filtered.out
    end

    test "is best-effort — malformed files are skipped (stderr), stdout stays parseable JSON" do
      result = okf("stats", fixture("malformed"), "--json")

      assert_equal 0, result.status
      assert_match(/skipped 2 unusable file\(s\)/, result.err)
      data = json(result)
      assert_equal 3, data.fetch("concepts") # the three that parse still count
      assert_equal({ "(root)" => 3 }, data.fetch("by_area"))
      refute_match(/note:/, result.out)
    end
  end
end
