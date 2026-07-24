# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf tags` end-to-end — the tag vocabulary as an inverted index (tag → the
# concepts carrying it), ordered by count. `--by type|area` re-cuts it per
# dimension for the curation question ("is this tag connective or scattered?"),
# and --type/--area narrow the concepts first. Advisory read: exit 0.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLITagsTest < CLIIntegrationCase
    test "lists tags by count with the concepts carrying each (exit 0)" do
      result = okf("tags", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/Tags — .*conformant \(2 distinct\)/, result.out)
      assert_match(/sales\s+3\s+Sales, Customers, Orders/, result.out)
      assert_match(/orders\s+1\s+Orders/, result.out)
      # ordered by count, so the tag on three concepts leads the tag on one
      assert_operator result.out.index("sales"), :<, result.out.index("orders")
    end

    test "--json emits the tag index as a machine substrate" do
      data = json(okf("tags", fixture("conformant"), "--json"))

      assert_equal 2, data.fetch("count")
      rows = data.fetch("tags")
      assert_equal %w[concepts count tag], rows.first.keys.sort
      assert_equal "sales", rows.first.fetch("tag")
      assert_equal 3, rows.first.fetch("count")
      assert_equal %w[datasets/sales tables/customers tables/orders], rows.first.fetch("concepts")
      assert_equal "orders", rows.last.fetch("tag")
    end

    test "--pretty implies --json and indents it" do
      result = okf("tags", fixture("conformant"), "--pretty")

      assert_equal 2, JSON.parse(result.out).fetch("count") # still JSON, no --json needed
      assert_match(/^  "count": 2,$/, result.out)
      assert_match(/^  "tags": \[$/, result.out)
      refute_match(/^  "count"/, okf("tags", fixture("conformant"), "--json").out) # compact by default
    end

    test "--by type groups the tags per concept type with within-group counts" do
      result = okf("tags", fixture("conformant"), "--by", "type")

      assert_equal 0, result.status
      assert_match(/Tags — .*conformant \(2 distinct, by type\)/, result.out)
      assert_match(/BigQuery Dataset \(1 tag\)/, result.out)
      assert_match(/BigQuery Table \(2 tags\)/, result.out)
      # `sales` is connective — it recurs in both groups, counted per group,
      # with the bundle-wide total beside the within-group count
      assert_match(%r{BigQuery Dataset \(1 tag\)\n\s+sales\s+1/3\s+Sales\n}, result.out)
      assert_match(%r{sales\s+2/3\s+Customers, Orders}, result.out)
    end

    test "--by area groups the tags per top-level area, labelled as folders" do
      result = okf("tags", fixture("conformant"), "--by", "area")

      assert_equal 0, result.status
      assert_match(/\(2 distinct, by area\)/, result.out)
      assert_match(%r{datasets/ \(1 tag\)\n\s+sales\s+1/3\s+Sales\n}, result.out)
      assert_match(%r{tables/ \(2 tags\)}, result.out)
      assert_match(/orders\s+1\s+Orders/, result.out)
      # groups sort by name: datasets/ before tables/
      assert_operator result.out.index("datasets/"), :<, result.out.index("tables/")
    end

    test "--by type --json gains a `by` key and nests the rows under `groups`" do
      data = json(okf("tags", fixture("conformant"), "--by", "type", "--json"))

      assert_equal "type", data.fetch("by")
      assert_equal 2, data.fetch("count") # distinct tags across the groups, not a group count
      groups = data.fetch("groups")
      assert_equal [ "BigQuery Dataset", "BigQuery Table" ], groups.map { |g| g.fetch("type") }
      assert_equal %w[count tags type], groups.first.keys.sort
      assert_equal 1, groups.first.fetch("count")
      assert_equal [ { "tag" => "sales", "count" => 1, "total" => 3, "concepts" => [ "datasets/sales" ] } ], groups.first.fetch("tags")
      assert_equal %w[sales orders], groups.last.fetch("tags").map { |row| row.fetch("tag") }
    end

    test "--by rows carry each tag's bundle-wide total, so spread reads per group" do
      result = okf("tags", fixture("shapely"), "--by", "area")

      assert_equal 0, result.status
      # `async` is spread over two areas — each group shows its share of the total
      assert_match(%r{flows/ \(2 tags\)\n\s+async\s+2/3\s+Activate, Suspend\n\s+flows\s+2\s+Activate, Suspend\n}, result.out)
      assert_match(%r{billing/ \(2 tags\)\n\s+async\s+1/3\s+Renew\n\s+billing\s+1\s+Renew\n}, result.out)
      # a tag local to its group shows a plain count — count/total only when they differ
      refute_match(%r{2/2}, result.out)
      assert_match(/state-machine\s+1\s+Status/, result.out)
    end

    test "--by area --json rows carry count and total per tag" do
      data = json(okf("tags", fixture("shapely"), "--by", "area", "--json"))

      flows = data.fetch("groups").find { |group| group.fetch("area") == "flows" }
      assert_equal [ { "tag" => "async", "count" => 2, "total" => 3, "concepts" => [ "flows/activate", "flows/suspend" ] },
                     { "tag" => "flows", "count" => 2, "total" => 2, "concepts" => [ "flows/activate", "flows/suspend" ] } ],
        flows.fetch("tags")
    end

    test "filters recompute totals over the narrowed set, so a filtered view stays self-consistent" do
      data = json(okf("tags", fixture("shapely"), "--area", "flows", "--by", "area", "--json"))

      async = data.fetch("groups").first.fetch("tags").find { |row| row.fetch("tag") == "async" }
      assert_equal 2, async.fetch("count")
      assert_equal 2, async.fetch("total") # the billing concept is narrowed away, and the total follows
    end

    test "--by area labels the root area bare, and only nested areas get a slash" do
      # The `rooted` fixture exists for this branch: no other fixture carries a
      # *tagged* root-level concept, so `(root)` — the one label printed without a
      # trailing slash — was unreachable and therefore unproven.
      result = okf("tags", fixture("rooted"), "--by", "area")

      assert_equal 0, result.status
      assert_match(/^\s{2}\(root\) \(2 tags\)$/, result.out, "the root area is named, and never as `(root)/`")
      refute_match(%r{\(root\)/}, result.out)
      assert_match(%r{^\s{2}services/ \(1 tag\)$}, result.out, "a nested area still carries its slash")
      assert_match(/governance\s+1\s+Charter/, result.out)
    end

    test "--by area --json carries the root area under its own key" do
      groups = json(okf("tags", fixture("rooted"), "--by", "area", "--json"))["groups"]

      assert_equal [ "(root)", "services" ], groups.map { |group| group["area"] },
        "the JSON keys the root by name — the trailing slash is a human-view flourish, not data"
      assert_equal %w[governance shared], groups.first["tags"].map { |tag| tag["tag"] }.sort
    end

    test "--by area --json keys each group by its area" do
      data = json(okf("tags", fixture("conformant"), "--by", "area", "--json"))

      assert_equal "area", data.fetch("by")
      assert_equal %w[datasets tables], data.fetch("groups").map { |g| g.fetch("area") }
      assert_equal 2, data.fetch("groups").last.fetch("tags").length
    end

    test "--by dir groups the tags by the full directory path, the root as (root)" do
      result = okf("tags", fixture("rooted"), "--by", "dir")

      assert_equal 0, result.status
      assert_match(/\(2 distinct, by dir\)/, result.out)
      assert_match(/^\s{2}\(root\) \(2 tags\)$/, result.out, "`.` is data; the human view says (root)")
      assert_match(%r{^\s{2}services/ \(1 tag\)$}, result.out)
      refute_match(%r{\(root\)/}, result.out)
    end

    test "--by dir keys the root group `.` in JSON, and groups by the whole path" do
      groups = json(okf("tags", fixture("rooted"), "--by", "dir", "--json"))

      assert_equal "dir", groups.fetch("by")
      assert_equal [ ".", "services" ], groups.fetch("groups").map { |group| group["dir"] },
        "the JSON says `.` — (root) is the human spelling, never the stored one"

      # where --by area rolls a nested concept up to its first segment, --by dir
      # keeps the path it actually lives at
      deep = json(okf("tags", fixture("edge-cases"), "--by", "dir", "--json"))
      assert_includes deep.fetch("groups").map { |group| group["dir"] }, "deeply/nested/path"
    end

    test "--dir narrows the concepts before the index is cut" do
      data = json(okf("tags", fixture("conformant"), "--dir", "TABLES", "--json"))
      assert_equal %w[sales orders], data.fetch("tags").map { |row| row.fetch("tag") }
      assert_equal 2, data.fetch("tags").first.fetch("count")

      assert_equal [ "deep" ], json(okf("tags", fixture("edge-cases"), "--dir", "deeply", "--json"))
        .fetch("tags").map { |row| row.fetch("tag") }
    end

    test "--dir composes with --by dir" do
      data = json(okf("tags", fixture("conformant"), "--dir", "datasets", "--by", "dir", "--json"))

      assert_equal [ "datasets" ], data.fetch("groups").map { |group| group["dir"] }
    end

    test "--by area and --area still work, and each warns once on stderr" do
      area = okf("tags", fixture("conformant"), "--by", "area", "--json")
      assert_equal 0, area.status
      assert_equal "warning: --by area is deprecated, use --by dir\n", area.err
      assert_equal %w[datasets tables], json(area).fetch("groups").map { |g| g.fetch("area") }

      filtered = okf("tags", fixture("conformant"), "--area", "tables", "--json")
      assert_equal "warning: --area is deprecated, use --dir\n", filtered.err

      both = okf("tags", fixture("conformant"), "--area", "tables", "--by", "area", "--json")
      assert_equal "warning: --area is deprecated, use --dir\nwarning: --by area is deprecated, use --by dir\n", both.err
    end

    test "an unknown --by dimension is a usage error (exit 2)" do
      result = okf("tags", fixture("conformant"), "--by", "colour")

      assert_equal 2, result.status
      assert_match(/invalid argument: --by colour/, result.err)
      assert_equal "", result.out
    end

    test "--type narrows the concepts before the index is cut" do
      result = okf("tags", fixture("conformant"), "--type", "BigQuery Table", "--json")
      data = json(result)

      assert_equal 0, result.status
      assert_equal 2, data.fetch("tags").first.fetch("count") # `sales` drops the dataset concept
      assert_equal %w[tables/customers tables/orders], data.fetch("tags").first.fetch("concepts")
    end

    test "--area narrows too, and both filters fold case" do
      data = json(okf("tags", fixture("conformant"), "--area", "TABLES", "--json"))

      assert_equal %w[sales orders], data.fetch("tags").map { |row| row.fetch("tag") }
      assert_equal 2, data.fetch("tags").first.fetch("count")
      assert_equal 1, json(okf("tags", fixture("conformant"), "--type", "bigquery dataset", "--json")).fetch("count")
    end

    test "a filter that matches nothing empties the index rather than failing" do
      result = okf("tags", fixture("conformant"), "--type", "Nope", "--json")

      assert_equal 0, result.status
      assert_equal 0, json(result).fetch("count")
      assert_equal [], json(result).fetch("tags")
    end

    test "the filters compose with --by" do
      data = json(okf("tags", fixture("conformant"), "--type", "BigQuery Dataset", "--by", "area", "--json"))

      assert_equal [ "datasets" ], data.fetch("groups").map { |g| g.fetch("area") } # tables/ narrowed away
      assert_equal 1, data.fetch("count")
    end

    test "--tag is not offered — tags takes only the dimensions orthogonal to it (exit 2)" do
      result = okf("tags", fixture("conformant"), "--tag", "sales")

      assert_equal 2, result.status
      assert_match(/invalid option: --tag/, result.err)
    end

    test "a bundle with no tags reports zero distinct, not an error" do
      empty = okf("tags", fixture("empty"))
      assert_equal 0, empty.status
      assert_match(/Tags — .*empty \(0 distinct\)/, empty.out)

      untagged = okf("tags", fixture("minimal")) # one concept, no tags key
      assert_equal 0, untagged.status
      assert_match(/\(0 distinct\)/, untagged.out)
      assert_equal [], json(okf("tags", fixture("minimal"), "--json")).fetch("tags")
    end

    test "--by over an untagged bundle prints the header and no groups" do
      result = okf("tags", fixture("minimal"), "--by", "type")

      assert_equal 0, result.status
      assert_match(/\(0 distinct, by type\)/, result.out)
      assert_equal [], json(okf("tags", fixture("minimal"), "--by", "type", "--json")).fetch("groups")
    end

    test "JSON names the bundle by its directory; a bundle named by path carries no slug" do
      data = json(okf("tags", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data.fetch("bundle")
      refute data.key?("slug")
      refute_match(/@/, okf("tags", fixture("conformant")).out.lines.first)
    end

    test "usage errors exit 2: a missing directory, no directory at all" do
      missing = okf("tags", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)

      bare = okf("tags")
      assert_equal 2, bare.status
      assert_match(/Usage: okf tags <dir\|@slug>/, bare.err)
    end

    test "is best-effort — malformed files are skipped (stderr), stdout stays parseable JSON" do
      result = okf("tags", fixture("malformed"), "--json")

      assert_equal 0, result.status
      assert_match(/skipped 2 unusable file\(s\)/, result.err)
      assert_equal 0, json(result).fetch("count") # the note went to stderr, not into stdout
      refute_match(/note:/, result.out)
    end
  end
end
