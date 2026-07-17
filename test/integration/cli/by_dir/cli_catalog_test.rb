# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf catalog` end-to-end — the concept inventory grouped by top-level area, with
# each row's metadata. An advisory read (exit 0); the --type/--area/--tag filters
# narrow it and --fields/--except project the JSON an agent pays tokens for.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLICatalogTest < CLIIntegrationCase
    test "groups concepts under their area, with the total in the header (exit 0)" do
      result = okf("catalog", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/Catalog — .*conformant \(3 concepts\)/, result.out)
      assert_match(/datasets\/ \(1\)/, result.out)
      assert_match(/tables\/ \(2\)/, result.out)
      assert_match(/Sales {2}·  BigQuery Dataset {2}·  ↳4/, result.out)
      assert_match(/One row per completed customer order\./, result.out)
    end

    # The area is the *top-level* directory, not the file's folder: a concept nested
    # three deep still catalogs under the area it hangs from.
    test "a deeply nested concept groups under its top-level area" do
      result = okf("catalog", fixture("edge-cases"))

      assert_match(/deeply\/ \(1\)/, result.out)
      assert_match(/\(root\) \(3\)/, result.out)
      refute_match(/deeply\/nested\/path/, result.out)
    end

    test "--json emits the bundle envelope and the full row shape" do
      data = json(okf("catalog", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      assert_equal 3, data.fetch("count")
      assert_equal 3, data.fetch("concepts").size
      keys = data.fetch("concepts").first.keys.sort
      assert_equal %w[area backlog_ref description dir id links_in links_out status tags timestamp title type], keys
      assert_equal "datasets/sales", data.fetch("concepts").first.fetch("id")
      assert_equal %w[sales orders], data.fetch("concepts").last.fetch("tags")
    end

    test "--pretty implies --json and indents it" do
      result = okf("catalog", fixture("minimal"), "--pretty")

      assert_equal 1, JSON.parse(result.out).fetch("count") # implies --json
      assert_match(/^\{\n  "bundle": /, result.out)         # …and indents it
      refute_match(/^\{"bundle"/, okf("catalog", fixture("minimal"), "--pretty").out)
      assert_match(/^\{"bundle"/, okf("catalog", fixture("minimal"), "--json").out) # compact without it
    end

    test "--fields keeps only the named properties (and implies --json)" do
      data = json(okf("catalog", fixture("conformant"), "--fields", "id,title"))

      assert_equal %w[id title], data.fetch("concepts").first.keys
      assert_equal "Sales", data.fetch("concepts").first.fetch("title")
      assert_equal 3, data.fetch("count") # the envelope is never projected away
    end

    test "--except drops the named properties (and implies --json)" do
      data = json(okf("catalog", fixture("conformant"), "--except", "tags,timestamp"))
      row = data.fetch("concepts").first

      refute row.key?("tags")
      refute row.key?("timestamp")
      assert_equal "datasets/sales", row.fetch("id")
    end

    test "field names match case-insensitively" do
      data = json(okf("catalog", fixture("conformant"), "--fields", "ID,Title"))

      assert_equal %w[id title], data.fetch("concepts").first.keys
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      result = okf("catalog", fixture("conformant"), "--fields", "id", "--except", "title")

      assert_equal 2, result.status
      assert_match(/mutually exclusive/, result.err)
    end

    test "an unknown field is a usage error naming the valid ones (exit 2)" do
      result = okf("catalog", fixture("conformant"), "--fields", "bogus")

      assert_equal 2, result.status
      assert_match(/unknown field\(s\): bogus/, result.err)
      assert_match(/available: id, title, type, description, tags/, result.err)
      assert_equal "", result.out
      assert_equal 2, okf("catalog", fixture("conformant"), "--except", "nope").status # --except too
    end

    test "--type selects one concept type, case-insensitively" do
      result = okf("catalog", fixture("conformant"), "--type", "BigQuery Table")

      assert_equal 0, result.status
      assert_match(/\(2 of 3 concepts\)/, result.out) # the header counts the narrowing
      refute_match(/Sales/, result.out)

      folded = json(okf("catalog", fixture("conformant"), "--type", "bigquery table", "--json"))
      assert_equal %w[tables/customers tables/orders], folded.fetch("concepts").map { |row| row["id"] }
    end

    test "--area selects a top-level area, case-insensitively, and takes `root`" do
      data = json(okf("catalog", fixture("conformant"), "--area", "TABLES", "--json"))
      assert_equal 2, data.fetch("count")
      assert_equal %w[tables tables], data.fetch("concepts").map { |row| row["area"] }

      # `root` is the (root) area spelled without shell quoting.
      rooted = json(okf("catalog", fixture("edge-cases"), "--area", "root", "--json"))
      assert_equal %w[links-in-fences reference-style target], rooted.fetch("concepts").map { |row| row["id"] }
    end

    test "--tag selects concepts carrying a tag, case-insensitively" do
      data = json(okf("catalog", fixture("conformant"), "--tag", "ORDERS", "--json"))

      assert_equal 1, data.fetch("count")
      assert_equal "tables/orders", data.fetch("concepts").first.fetch("id")
    end

    test "a filter composes with a projection" do
      data = json(okf("catalog", fixture("conformant"), "--type", "BigQuery Table", "--fields", "id"))

      assert_equal [ { "id" => "tables/customers" }, { "id" => "tables/orders" } ], data.fetch("concepts")
    end

    test "a filter matching nothing is an empty list, not an error (exit 0)" do
      result = okf("catalog", fixture("conformant"), "--tag", "nosuchtag", "--json")

      assert_equal 0, result.status
      assert_equal 0, json(result).fetch("count")
      assert_equal [], json(result).fetch("concepts")
      assert_match(/\(0 of 3 concepts\)/, okf("catalog", fixture("conformant"), "--tag", "nosuchtag").out)
    end

    # The identity contract: `bundle` is always the directory, `slug` only ever a
    # registry slug — so a row resolves to <bundle>/<id>.md without a second lookup.
    test "a bundle named by path carries no slug key" do
      data = json(okf("catalog", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      refute data.key?("slug")
      refute_match(/@/, okf("catalog", fixture("conformant")).out.lines.first)
    end

    test "best-effort read: malformed files are skipped (stderr), stdout stays valid" do
      result = okf("catalog", fixture("malformed"))
      assert_equal 0, result.status
      assert_match(/skipped 2 file\(s\) with invalid frontmatter/, result.err)
      assert_match(/Good {2}·  Note/, result.out) # the three that parse still catalog

      machine = okf("catalog", fixture("malformed"), "--json")
      assert_equal 3, json(machine).fetch("count") # the note went to stderr, so this parses
    end

    test "an empty bundle catalogs to zero concepts, not a crash" do
      result = okf("catalog", fixture("empty"))
      assert_equal 0, result.status
      assert_match(/\(0 concepts\)/, result.out)

      assert_equal [], json(okf("catalog", fixture("empty"), "--json")).fetch("concepts")
    end

    test "usage errors exit 2: a missing directory, a bad flag, no directory at all" do
      missing = okf("catalog", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)

      bad_flag = okf("catalog", fixture("conformant"), "--nope")
      assert_equal 2, bad_flag.status
      assert_match(/invalid option: --nope/, bad_flag.err)

      assert_equal 2, okf("catalog").status
    end
  end
end
