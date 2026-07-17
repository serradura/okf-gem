# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf files` end-to-end — the file tree: every concept as a path, grouped by the
# folder it actually lives in (not by area, as `catalog` groups). An advisory read
# (exit 0), narrowed by the same --type/--area/--tag filters and projected by
# --fields/--except.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIFilesTest < CLIIntegrationCase
    test "lists filenames under their folder, with the total in the header (exit 0)" do
      result = okf("files", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/Files — .*conformant \(3 files\)/, result.out)
      assert_match(/datasets\/\n {4}sales\.md {2}Sales/, result.out)
      assert_match(/tables\/\n {4}customers\.md {2}Customers\n {4}orders\.md {5}Orders/, result.out) # names pad to a column
    end

    # Where `catalog` rolls a nested concept up to its top-level area, `files` shows
    # the folder on disk — the two views answer different questions.
    test "groups by the full folder, not the top-level area" do
      result = okf("files", fixture("edge-cases"))

      assert_match(/deeply\/nested\/path\/\n {4}concept\.md {2}Deep/, result.out)
      assert_match(/\(root\)\n {4}links-in-fences\.md/, result.out)
    end

    test "--json emits the bundle envelope and the row shape, path first" do
      data = json(okf("files", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      assert_equal 3, data.fetch("count")
      assert_equal %w[path id dir type title description], data.fetch("files").first.keys
      assert_equal "datasets/sales.md", data.fetch("files").first.fetch("path")
      assert_equal "datasets", data.fetch("files").first.fetch("dir")
    end

    test "--pretty implies --json and indents it" do
      result = okf("files", fixture("minimal"), "--pretty")

      assert_equal "note.md", JSON.parse(result.out).fetch("files").first.fetch("path") # implies --json
      assert_match(/^\{\n  "bundle": /, result.out)                                     # …and indents it
      assert_match(/^\{"bundle"/, okf("files", fixture("minimal"), "--json").out)       # compact without it
    end

    test "--fields keeps only the named properties (and implies --json)" do
      data = json(okf("files", fixture("conformant"), "--fields", "path,title"))

      assert_equal %w[path title], data.fetch("files").first.keys
      assert_equal "Sales", data.fetch("files").first.fetch("title")
      assert_equal 3, data.fetch("count") # the envelope is never projected away
    end

    test "--except drops the named properties (and implies --json)" do
      data = json(okf("files", fixture("conformant"), "--except", "description,type"))
      row = data.fetch("files").first

      assert_equal %w[path id dir title], row.keys
      refute row.key?("description")
    end

    test "field names match case-insensitively" do
      data = json(okf("files", fixture("conformant"), "--fields", "PATH,Title"))

      assert_equal %w[path title], data.fetch("files").first.keys
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      result = okf("files", fixture("conformant"), "--fields", "path", "--except", "title")

      assert_equal 2, result.status
      assert_match(/mutually exclusive/, result.err)
    end

    test "an unknown field is a usage error naming the valid ones (exit 2)" do
      result = okf("files", fixture("conformant"), "--fields", "bogus")

      assert_equal 2, result.status
      assert_match(/unknown field\(s\): bogus/, result.err)
      assert_match(/available: path, id, dir, type, title, description/, result.err)
      assert_equal "", result.out
      assert_equal 2, okf("files", fixture("conformant"), "--except", "nope").status # --except too
    end

    test "--type selects one concept type, case-insensitively" do
      result = okf("files", fixture("conformant"), "--type", "BigQuery Dataset")

      assert_equal 0, result.status
      assert_match(/\(1 of 3 files\)/, result.out) # the header counts the narrowing
      assert_match(/sales\.md {2}Sales/, result.out)
      refute_match(/customers\.md/, result.out)

      folded = json(okf("files", fixture("conformant"), "--type", "bigquery dataset", "--json"))
      assert_equal [ "datasets/sales.md" ], folded.fetch("files").map { |row| row["path"] }
    end

    test "--area selects a top-level area, case-insensitively, and takes `root`" do
      data = json(okf("files", fixture("conformant"), "--area", "TABLES", "--json"))
      assert_equal %w[tables/customers.md tables/orders.md], data.fetch("files").map { |row| row["path"] }

      # --area is the *top-level* area, so it reaches a file nested below it; the row's
      # own `dir` stays the folder on disk.
      nested = json(okf("files", fixture("edge-cases"), "--area", "deeply", "--json"))
      assert_equal [ "deeply/nested/path/concept.md" ], nested.fetch("files").map { |row| row["path"] }
      assert_equal "deeply/nested/path", nested.fetch("files").first.fetch("dir")

      rooted = json(okf("files", fixture("edge-cases"), "--area", "root", "--json"))
      assert_equal 3, rooted.fetch("count")
    end

    # The row carries no `tags` key, but --tag still filters: the narrowing runs over
    # the catalog metadata behind the view, not over the projected row.
    test "--tag selects concepts carrying a tag, case-insensitively" do
      data = json(okf("files", fixture("conformant"), "--tag", "ORDERS", "--json"))

      assert_equal 1, data.fetch("count")
      assert_equal "tables/orders.md", data.fetch("files").first.fetch("path")
      refute data.fetch("files").first.key?("tags")
    end

    test "a filter composes with a projection" do
      data = json(okf("files", fixture("conformant"), "--area", "tables", "--fields", "path"))

      assert_equal [ { "path" => "tables/customers.md" }, { "path" => "tables/orders.md" } ], data.fetch("files")
    end

    test "a filter matching nothing is an empty list, not an error (exit 0)" do
      result = okf("files", fixture("conformant"), "--tag", "nosuchtag", "--json")

      assert_equal 0, result.status
      assert_equal 0, json(result).fetch("count")
      assert_equal [], json(result).fetch("files")
      assert_match(/\(0 of 3 files\)/, okf("files", fixture("conformant"), "--tag", "nosuchtag").out)
    end

    # The identity contract: `bundle` is always the directory, `slug` only ever a
    # registry slug — so a row's `path` resolves under `bundle` without a second lookup.
    test "a bundle named by path carries no slug key" do
      data = json(okf("files", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      refute data.key?("slug")
      refute_match(/@/, okf("files", fixture("conformant")).out.lines.first)
    end

    test "best-effort read: malformed files are skipped (stderr), stdout stays valid" do
      result = okf("files", fixture("malformed"))
      assert_equal 0, result.status
      assert_match(/skipped 2 file\(s\) with invalid frontmatter/, result.err)
      assert_match(/good\.md {8}Good/, result.out) # the three that parse still list

      machine = okf("files", fixture("malformed"), "--json")
      assert_equal %w[blank-type.md good.md no-type.md], json(machine).fetch("files").map { |row| row["path"] }
    end

    test "an empty bundle lists zero files, not a crash" do
      result = okf("files", fixture("empty"))
      assert_equal 0, result.status
      assert_match(/\(0 files\)/, result.out)

      assert_equal [], json(okf("files", fixture("empty"), "--json")).fetch("files")
    end

    test "usage errors exit 2: a missing directory, a bad flag, no directory at all" do
      missing = okf("files", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)

      bad_flag = okf("files", fixture("conformant"), "--nope")
      assert_equal 2, bad_flag.status
      assert_match(/invalid option: --nope/, bad_flag.err)

      banner = okf("files")
      assert_equal 2, banner.status
      assert_match(/Usage: okf files <bundle-dir>/, banner.err)
    end
  end
end
