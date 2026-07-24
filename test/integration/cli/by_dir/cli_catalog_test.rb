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
      assert_equal %w[backlog_ref description dir id links_in links_out status tags timestamp title top_dir type], keys
      assert_equal "datasets/sales", data.fetch("concepts").first.fetch("id")
      assert_equal %w[sales orders], data.fetch("concepts").last.fetch("tags")
    end

    # A title-less concept must wear the SAME fallback label everywhere. The graph
    # node falls back blank-aware to File.basename(id) — "thing"; the catalog fell
    # back (title || id) to the whole id — "area/thing" — so one concept answered to
    # two names across two views of the same bundle. A blank `title: ""` was worse:
    # it slipped past the nil-only `||` and cataloged as an empty label.
    test "a title-less concept falls back to its basename, matching the graph node" do
      concepts = json(okf("catalog", fixture("untitled"), "--json")).fetch("concepts")
      nodes = json(okf("graph", fixture("untitled"), "--json", "--minimal")).fetch("nodes")
      title_of = ->(rows, id) { rows.find { |row| row["id"] == id }.fetch("title") }

      assert_equal "thing", title_of.call(nodes, "area/thing"), "the graph already falls back to the basename"
      assert_equal "thing", title_of.call(concepts, "area/thing"), "the catalog must not diverge — same concept, same label"
      assert_equal "blank", title_of.call(concepts, "area/blank"), "a blank title falls back too, never an empty label"
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
      assert_equal %w[tables tables], data.fetch("concepts").map { |row| row["top_dir"] }

      # `root` is the (root) area spelled without shell quoting.
      rooted = json(okf("catalog", fixture("edge-cases"), "--area", "root", "--json"))
      assert_equal %w[links-in-fences reference-style target], rooted.fetch("concepts").map { |row| row["id"] }
    end

    test "--dir selects a directory and everything beneath it" do
      # One rule: a concept matches its own dir and any ancestor of it. So the
      # empty intermediate `deeply` still reaches the concept three levels down,
      # which is what --area could only do for the *first* segment.
      nested = json(okf("catalog", fixture("edge-cases"), "--dir", "deeply", "--json"))
      assert_equal [ "deeply/nested/path/concept" ], nested.fetch("concepts").map { |row| row["id"] }
      assert_equal "deeply/nested/path", nested.fetch("concepts").first.fetch("dir")

      assert_equal 1, json(okf("catalog", fixture("edge-cases"), "--dir", "deeply/nested", "--json")).fetch("count")
      assert_equal 1, json(okf("catalog", fixture("edge-cases"), "--dir", "deeply/nested/path", "--json")).fetch("count")
      # a path segment is matched whole — `deep` is not a prefix of `deeply`
      assert_equal 0, json(okf("catalog", fixture("edge-cases"), "--dir", "deep", "--json")).fetch("count")
    end

    test "--dir . is the root alone, spellable as `root`, and folds case" do
      # Nothing starts with "./", so the one prefix rule already means root-only —
      # no special case, and `root` is the same thing without the shell quoting.
      dot = json(okf("catalog", fixture("edge-cases"), "--dir", ".", "--json"))
      assert_equal %w[links-in-fences reference-style target], dot.fetch("concepts").map { |row| row["id"] }
      assert_equal dot, json(okf("catalog", fixture("edge-cases"), "--dir", "root", "--json"))
      assert_equal dot, json(okf("catalog", fixture("edge-cases"), "--dir", "ROOT", "--json"))

      assert_equal 2, json(okf("catalog", fixture("conformant"), "--dir", "TABLES", "--json")).fetch("count")
    end

    test "--dir composes with the other filters and with a projection" do
      data = json(okf("catalog", fixture("conformant"), "--dir", "tables", "--tag", "orders", "--fields", "id"))
      assert_equal [ { "id" => "tables/orders" } ], data.fetch("concepts")

      empty = okf("catalog", fixture("conformant"), "--dir", "tables", "--type", "BigQuery Dataset", "--json")
      assert_equal 0, empty.status
      assert_equal [], json(empty).fetch("concepts")
    end

    test "--area still filters, and says on stderr that it is deprecated" do
      result = okf("catalog", fixture("conformant"), "--area", "tables", "--json")

      assert_equal 0, result.status
      assert_equal "warning: --area is deprecated, use --dir\n", result.err
      assert_equal 2, json(result).fetch("count") # the old behavior, unchanged
      refute_match(/warning/, result.out) # the warning never pollutes the machine substrate
      assert_empty okf("catalog", fixture("conformant"), "--dir", "tables", "--json").err
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
      assert_match(/skipped 2 unusable file\(s\)/, result.err)
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
