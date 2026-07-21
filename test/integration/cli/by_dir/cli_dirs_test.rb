# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf dirs` end-to-end — the bundle's directories (its clusters) with the count
# of concepts living *directly* in each. The shape view: where the concepts are,
# before what they are. Advisory read: exit 0.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIDirsTest < CLIIntegrationCase
    test "lists every dir with its direct count, total last (exit 0)" do
      result = okf("dirs", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/^Dirs — .*conformant$/, result.out)
      assert_match(/^  Dir\s+Concepts$/, result.out)
      assert_match(/^  \(root\)\s+0$/, result.out)
      assert_match(/^  datasets\s+1$/, result.out)
      assert_match(/^  tables\s+2$/, result.out)
      assert_match(/^  3 dirs · 3 concepts$/, result.out)
    end

    test "the root dir prints as (root), never as `.`" do
      result = okf("dirs", fixture("rooted"))

      assert_match(/^  \(root\)/, result.out)
      refute_match(/^  \.\s/, result.out)
      assert_match(/^  services/, result.out)
      assert_match(/^  2 dirs · 2 concepts$/, result.out)
    end

    test "an empty intermediate dir is a row of its own, at count 0" do
      # edge-cases holds one concept at deeply/nested/path and nothing in the two
      # dirs above it — the rows that only exist because the tree has to connect.
      result = okf("dirs", fixture("edge-cases"))

      assert_match(/^  \(root\)\s+3$/, result.out)
      assert_match(/^  deeply\s+0$/, result.out)
      assert_match(/^  deeply\/nested\s+0$/, result.out)
      assert_match(/^  deeply\/nested\/path\s+1$/, result.out)
      assert_match(/^  4 dirs · 4 concepts$/, result.out)
    end

    test "--json carries `.` for the root, the direct count, and the subdirs" do
      data = json(okf("dirs", fixture("conformant"), "--json"))

      assert_equal %w[bundle count dirs total], data.keys.sort
      assert_equal 3, data.fetch("count")
      assert_equal 3, data.fetch("total")
      assert_equal({ "dir" => ".", "count" => 0, "subdirs" => %w[datasets tables] }, data.fetch("dirs").first)
      assert_equal [ ".", "datasets", "tables" ], data.fetch("dirs").map { |row| row["dir"] }
      assert_equal [ [], [] ], data.fetch("dirs").drop(1).map { |row| row["subdirs"] }
    end

    test "--json says `.` where the table says (root)" do
      data = json(okf("dirs", fixture("rooted"), "--json"))

      assert_equal [ ".", "services" ], data.fetch("dirs").map { |row| row["dir"] }
      refute_match(/\(root\)/, okf("dirs", fixture("rooted"), "--json").out)
    end

    test "--pretty implies --json and indents it" do
      result = okf("dirs", fixture("minimal"), "--pretty")

      assert_equal 1, JSON.parse(result.out).fetch("total")
      assert_match(/^  "total": 1,$/, result.out)
      refute_match(/\n  "total"/, okf("dirs", fixture("minimal"), "--json").out)
    end

    test "an empty bundle has no dirs and no crash" do
      result = okf("dirs", fixture("empty"))

      assert_equal 0, result.status
      assert_match(/^  0 dirs · 0 concepts$/, result.out)
      refute_match(/Concepts/, result.out) # no header over an empty table

      data = json(okf("dirs", fixture("empty"), "--json"))
      assert_equal [], data.fetch("dirs")
      assert_equal 0, data.fetch("total")
    end

    test "the listing is physical: a dir with only an index.md is still a dir" do
      # structural/sub holds an index.md and no concepts — `dirs` follows
      # directory_index, which is grouped by the file's path.
      data = json(okf("dirs", fixture("structural"), "--json"))

      assert_includes data.fetch("dirs").map { |row| row["dir"] }, "sub"
      assert_equal 0, data.fetch("dirs").find { |row| row["dir"] == "sub" }.fetch("count")
    end

    test "JSON names the bundle by its directory; a bundle named by path carries no slug" do
      data = json(okf("dirs", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      refute data.key?("slug")
    end

    test "usage errors exit 2: a missing directory, no directory at all, an unknown flag" do
      missing = okf("dirs", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)

      bare = okf("dirs")
      assert_equal 2, bare.status
      assert_match(/Usage: okf dirs <dir\|@slug>/, bare.err)

      # `dirs` is the shape of the bundle, not a narrowed read of it
      filtered = okf("dirs", fixture("conformant"), "--type", "BigQuery Table")
      assert_equal 2, filtered.status
      assert_match(/invalid option: --type/, filtered.err)
      assert_empty filtered.out
    end

    test "-h prints the usage and exits 0 without reading a bundle" do
      result = okf("dirs", "-h")

      assert_equal 0, result.status
      assert_match(/Usage: okf dirs <dir\|@slug>/, result.out)
    end

    test "is best-effort — malformed files are skipped (stderr), stdout stays parseable JSON" do
      result = okf("dirs", fixture("malformed"), "--json")

      assert_equal 0, result.status
      assert_match(/skipped 2 unusable file\(s\)/, result.err)
      assert_equal 3, json(result).fetch("total")
      refute_match(/note:/, result.out)
    end

    test "the verb is listed in the map, under the read group" do
      assert_match(/^  dirs {6}<dir\|@slug> \[--json\] +list the bundle's dirs/, okf("help").out)
    end
  end
end
