# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf types` end-to-end — the concept-type vocabulary as an inverted index
# (type → the concepts of it), ordered by count. The same back half as `tags`,
# cut on the other axis, so it takes the filters orthogonal to it: --area and
# --tag, never --type. Advisory read: exit 0.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLITypesTest < CLIIntegrationCase
    test "lists types by count with the concepts of each (exit 0)" do
      result = okf("types", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/Types — .*conformant \(2 distinct\)/, result.out)
      assert_match(/BigQuery Table\s+2\s+Customers, Orders/, result.out)
      assert_match(/BigQuery Dataset\s+1\s+Sales/, result.out)
    end

    test "rows order by count, ties by name" do
      busiest = json(okf("types", fixture("conformant"), "--json")).fetch("types")
      assert_equal [ "BigQuery Table", "BigQuery Dataset" ], busiest.map { |row| row.fetch("type") }
      assert_equal [ 2, 1 ], busiest.map { |row| row.fetch("count") }

      # rooted carries two types at count 1 apiece — the tie breaks by name
      tied = json(okf("types", fixture("rooted"), "--json")).fetch("types")
      assert_equal [ 1, 1 ], tied.map { |row| row.fetch("count") }
      assert_equal %w[Decision Service], tied.map { |row| row.fetch("type") }
    end

    test "every spelling of an unusable type lands in one Untyped bucket" do
      # §9.2 rejects a blank `type` exactly as it rejects a missing one, so the
      # index must not sort them apart: `malformed` carries one of each, and a
      # whitespace-only type used to earn its own row labelled with spaces.
      rows = json(okf("types", fixture("malformed"), "--json")).fetch("types")

      untyped = rows.find { |row| row.fetch("type") == "Untyped" }
      assert_equal %w[blank-type no-type], untyped.fetch("concepts").sort,
        "the blank type and the missing one are the same answer, so they share a bucket"
      assert_equal 2, untyped.fetch("count")
      refute_includes rows.map { |row| row.fetch("type") }, "  ", "no row is labelled with whitespace"
      assert_empty rows.map { |row| row.fetch("type") }.select { |type| type.strip.empty? }
    end

    test "--json emits the type index as a machine substrate" do
      data = json(okf("types", fixture("conformant"), "--json"))

      assert_equal 2, data.fetch("count")
      rows = data.fetch("types")
      assert_equal %w[concepts count type], rows.first.keys.sort
      assert_equal "BigQuery Table", rows.first.fetch("type")
      assert_equal %w[tables/customers tables/orders], rows.first.fetch("concepts")
      assert_equal [ "datasets/sales" ], rows.last.fetch("concepts")
    end

    test "--pretty implies --json and indents it" do
      result = okf("types", fixture("minimal"), "--pretty")

      assert_equal 1, JSON.parse(result.out).fetch("count") # still JSON, no --json needed
      assert_match(/^  "count": 1,$/, result.out)
      assert_match(/^  "types": \[$/, result.out)
      assert_match(/^      "type": "Note",$/, result.out)
      refute_match(/\n  "count"/, okf("types", fixture("minimal"), "--json").out) # compact by default
    end

    test "--area narrows to one top-level area, `root` naming the bundle root" do
      tables = json(okf("types", fixture("conformant"), "--area", "tables", "--json"))
      assert_equal 1, tables.fetch("count") # BigQuery Dataset lives in datasets/, and drops
      assert_equal "BigQuery Table", tables.fetch("types").first.fetch("type")
      assert_equal 2, tables.fetch("types").first.fetch("count")

      rooted = json(okf("types", fixture("edge-cases"), "--area", "root", "--json"))
      assert_equal %w[links-in-fences reference-style target], rooted.fetch("types").first.fetch("concepts")
    end

    test "--dir narrows by directory prefix, `root` naming the bundle root" do
      tables = json(okf("types", fixture("conformant"), "--dir", "tables", "--json"))
      assert_equal 1, tables.fetch("count") # BigQuery Dataset lives in datasets/, and drops
      assert_equal 2, tables.fetch("types").first.fetch("count")

      # the prefix rule reaches below the named dir, where --area only ever saw
      # the first segment
      nested = json(okf("types", fixture("edge-cases"), "--dir", "deeply", "--json"))
      assert_equal [ "deeply/nested/path/concept" ], nested.fetch("types").first.fetch("concepts")

      rooted = json(okf("types", fixture("edge-cases"), "--dir", "root", "--json"))
      assert_equal %w[links-in-fences reference-style target], rooted.fetch("types").first.fetch("concepts")
      assert_equal rooted, json(okf("types", fixture("edge-cases"), "--dir", ".", "--json"))
    end

    test "--area still narrows, and warns on stderr" do
      result = okf("types", fixture("conformant"), "--area", "tables", "--json")

      assert_equal 0, result.status
      assert_equal "warning: --area is deprecated, use --dir\n", result.err
      assert_equal 1, json(result).fetch("count")
      assert_empty okf("types", fixture("conformant"), "--dir", "tables", "--json").err
    end

    test "--tag narrows to the concepts carrying a tag" do
      data = json(okf("types", fixture("conformant"), "--tag", "orders", "--json"))

      assert_equal 1, data.fetch("count")
      assert_equal [ "tables/orders" ], data.fetch("types").first.fetch("concepts")
      assert_equal 1, data.fetch("types").first.fetch("count") # counted after the narrowing
    end

    test "the filters fold case, and one matching nothing empties the index" do
      assert_equal 2, json(okf("types", fixture("conformant"), "--area", "TABLES", "--json")).fetch("types").first.fetch("count")
      assert_equal 2, json(okf("types", fixture("conformant"), "--tag", "SALES", "--json")).fetch("count")

      result = okf("types", fixture("conformant"), "--tag", "nope", "--json")
      assert_equal 0, result.status
      assert_equal [], json(result).fetch("types")
    end

    test "--type is not offered — types takes only the dimensions orthogonal to it (exit 2)" do
      result = okf("types", fixture("conformant"), "--type", "BigQuery Table")

      assert_equal 2, result.status
      assert_match(/invalid option: --type/, result.err)
      assert_equal "", result.out
    end

    test "an empty bundle reports zero distinct, not an error" do
      result = okf("types", fixture("empty"))

      assert_equal 0, result.status
      assert_match(/Types — .*empty \(0 distinct\)/, result.out)
      assert_equal [], json(okf("types", fixture("empty"), "--json")).fetch("types")
    end

    test "JSON names the bundle by its directory; a bundle named by path carries no slug" do
      data = json(okf("types", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      refute data.key?("slug")
      assert_match(/^Types — #{Regexp.escape(fixture("conformant"))} \(2 distinct\)$/, okf("types", fixture("conformant")).out)
    end

    test "is best-effort — malformed files are skipped (stderr), stdout stays parseable JSON" do
      result = okf("types", fixture("malformed"), "--json")

      assert_equal 0, result.status
      assert_match(/skipped 2 unusable file\(s\)/, result.err)
      assert_equal 2, json(result).fetch("count") # Note, plus the one Untyped bucket the unusable types share
      assert_equal [ "good" ], json(result).fetch("types").find { |row| row.fetch("type") == "Note" }.fetch("concepts")
      refute_match(/note:/, result.out)
    end
  end
end
