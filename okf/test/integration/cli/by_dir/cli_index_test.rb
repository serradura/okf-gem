# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf index` end to end — the §6 progressive-disclosure map over the committed
# fixtures: every directory that holds concepts or carries an index.md, with its
# authored body, its type/tag rollup, its child directories, and (where no
# index.md was authored) the listing synthesized from the concepts there. The
# "orient before you read" view: advisory, exit 0.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIIndexTest < CLIIntegrationCase
    test "the map prints each directory with its authored body, rollup and subdirs" do
      result = okf("index", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/\AIndex map — #{Regexp.escape(fixture("conformant"))} \(3 directories\)/, result.out)
      assert_match(/^  \(root\)  ·  0 concepts$/, result.out)
      assert_match(/^    → datasets\/  tables\/$/, result.out, "the root lists its child directories")
      assert_match(/^  datasets\/  ·  1 concept · BigQuery Dataset 1$/, result.out, "singular noun and type rollup")
      assert_match(/^    # Sales Knowledge$/, result.out, "the root's authored index body is printed verbatim")
      assert_match(/^    \* \[Orders\]\(tables\/orders\.md\) - one row per order$/, result.out)
    end

    test "a directory with no index.md is marked and gets a synthesized listing" do
      result = okf("index", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/^  tables\/  \(no index\.md\)  ·  2 concepts · BigQuery Table 2$/, result.out)
      assert_match(/^    • Orders — One row per completed customer order\.$/, result.out)
      assert_match(/^    • Customers — One row per customer\.$/, result.out)
      refute_match(/^    • Sales —/, result.out, "datasets/ authored an index.md, so nothing is synthesized for it")
    end

    test "--json is the envelope plus one row per directory" do
      data = json(okf("index", fixture("conformant"), "--json"))

      assert_equal fixture("conformant"), data["bundle"]
      assert_equal 3, data["count"]
      assert_equal [ ".", "datasets", "tables" ], data["directories"].map { |row| row["dir"] }

      root = data["directories"].first
      assert_equal %w[dir ancestor index_path present synthesized count types tags subdirs body listing], root.keys
      assert_equal "index.md", root["index_path"]
      assert_equal true, root["present"]
      assert_equal false, root["synthesized"]
      assert_equal %w[datasets tables], root["subdirs"]
      assert_match(/\A# Sales Knowledge\n/, root["body"])

      tables = data["directories"].last
      assert_equal "tables/index.md", tables["index_path"], "the path an index.md would take, authored or not"
      assert_equal false, tables["present"]
      assert_equal true, tables["synthesized"]
      assert_nil tables["body"], "no index.md means no authored body"
      assert_equal({ "BigQuery Table" => 2 }, tables["types"])
      assert_equal({ "sales" => 2, "orders" => 1 }, tables["tags"])
      assert_equal [ "tables/customers", "tables/orders" ], tables["listing"].map { |item| item["id"] }
      assert_equal %w[id title description type tags], tables["listing"].first.keys
    end

    # The synthesized listing shares the catalog's title fallback: a title-less
    # concept must list under its basename, not its full id — the label the graph
    # node already uses. Same defect, same fix as the catalog (see cli_catalog_test).
    test "a synthesized listing falls back a title-less concept to its basename" do
      data = json(okf("index", fixture("untitled"), "--json"))
      area = data["directories"].find { |dir| dir["dir"] == "area" }
      titles = area["listing"].each_with_object({}) { |item, map| map[item["id"]] = item["title"] }

      assert_equal "thing", titles.fetch("area/thing"), "the listing must not fall back to the full id 'area/thing'"
      assert_equal "blank", titles.fetch("area/blank"), "a blank title falls back too, never an empty label"
    end

    test "--pretty implies --json and indents the same payload" do
      pretty = okf("index", fixture("conformant"), "--pretty")
      compact = okf("index", fixture("conformant"), "--json")

      assert_equal 0, pretty.status
      assert_equal JSON.parse(compact.out), JSON.parse(pretty.out), "the same JSON, differently spelled"
      assert_match(/^  "bundle": /, pretty.out, "--pretty indents")
      refute_match(/^  "bundle": /, compact.out)
      assert_operator pretty.out.bytesize, :>, compact.out.bytesize
    end

    test "--area narrows to the named directory; `root` names the bundle root" do
      tables = okf("index", fixture("conformant"), "--area", "tables")

      assert_equal 0, tables.status
      assert_match(/\(1 directory\)/, tables.out, "the noun follows the count")
      assert_match(/^  tables\/  \(no index\.md\)/, tables.out)
      refute_match(/datasets/, tables.out)

      root = okf("index", fixture("conformant"), "--area", "root")
      assert_match(/^  \(root\)  ·  0 concepts$/, root.out)
      assert_match(/# Sales Knowledge/, root.out)
      refute_match(/^  tables\//, root.out)
    end

    test "--area is repeatable and case-insensitive" do
      data = json(okf("index", fixture("conformant"), "--area", "TABLES", "--area", "datasets", "--json"))

      assert_equal 2, data["count"]
      assert_equal %w[datasets tables], data["directories"].map { |row| row["dir"] }
    end

    test "--dir narrows to the named directory and everything beneath it" do
      tables = okf("index", fixture("conformant"), "--dir", "tables", "--no-ancestors")

      assert_equal 0, tables.status
      assert_match(/\(1 directory\)/, tables.out)
      assert_match(%r{^  tables/  \(no index\.md\)}, tables.out)
      refute_match(/datasets/, tables.out)

      # where --area named one directory exactly, --dir names a subtree: the
      # empty intermediates below `deeply` come along.
      data = json(okf("index", fixture("edge-cases"), "--dir", "deeply", "--no-ancestors", "--json"))
      assert_equal %w[deeply deeply/nested deeply/nested/path], data["directories"].map { |row| row["dir"] }

      root = okf("index", fixture("conformant"), "--dir", "root")
      assert_match(/^  \(root\)  ·  0 concepts$/, root.out)
      refute_match(%r{^  tables/}, root.out) # `.` is a prefix of nothing
    end

    test "--dir is repeatable and case-insensitive, and two bases share one chain" do
      data = json(okf("index", fixture("conformant"), "--dir", "TABLES", "--dir", "datasets", "--json"))

      assert_equal 3, data["count"]
      assert_equal [ ".", "datasets", "tables" ], data["directories"].map { |row| row["dir"] },
        "the root is both dirs' ancestor and is listed once"

      lean = json(okf("index", fixture("conformant"), "--dir", "TABLES", "--dir", "datasets", "--no-ancestors", "--json"))
      assert_equal %w[datasets tables], lean["directories"].map { |row| row["dir"] }
    end

    test "--depth truncates the map, counting levels from the bundle root" do
      # The lever the map needed: on a deep bundle every directory is a section,
      # and there is no way to ask for the top of the tree without naming each
      # branch. `--dir root` gives one directory, never one *level*.
      assert_equal %w[. deeply], map_dirs(okf("index", fixture("edge-cases"), "--depth", "1", "--json"))
      assert_equal [ "." ], map_dirs(okf("index", fixture("edge-cases"), "--depth", "0", "--json"))
      assert_equal %w[. deeply deeply/nested deeply/nested/path],
        map_dirs(okf("index", fixture("edge-cases"), "--depth", "9", "--json"))

      human = okf("index", fixture("edge-cases"), "--depth", "1", "--no-body")
      assert_equal 0, human.status
      assert_match(/\(2 directories\)/, human.out)
      refute_match(%r{deeply/nested}, human.out)
    end

    test "--dir plus --depth counts the levels from the named directory" do
      # Relative, so a reader never has to know how deep the dir they named is:
      # `--dir deeply --depth 1` is "deeply and one level under it" wherever
      # deeply happens to sit.
      # --no-ancestors so the descent is the only thing under test here
      assert_equal %w[deeply deeply/nested],
        map_dirs(okf("index", fixture("edge-cases"), "--dir", "deeply", "--depth", "1", "--no-ancestors", "--json"))
      assert_equal [ "deeply" ],
        map_dirs(okf("index", fixture("edge-cases"), "--dir", "deeply", "--depth", "0", "--no-ancestors", "--json"))
      assert_equal [ "." ],
        map_dirs(okf("index", fixture("edge-cases"), "--dir", "root", "--depth", "3", "--json")),
        "`.` is a prefix of nothing, so no depth reaches out of the root"
    end

    test "--depth composes with --no-body and a projection" do
      data = json(okf("index", fixture("edge-cases"), "--depth", "1", "--fields", "dir,count"))

      assert_equal [ { "dir" => ".", "count" => 3 }, { "dir" => "deeply", "count" => 0 } ], data.fetch("directories")
      assert_equal 2, data.fetch("count")
    end

    test "--dir carries the chain up to the root, so a branch is never shown adrift" do
      # The map's whole job is orientation, and a branch shown with nothing above
      # it has dropped the authored context that says what the branch *is* — the
      # root index.md's prose first among it. The chain comes by default; the
      # rows are marked, because the reader did not ask for them.
      data = json(okf("index", fixture("edge-cases"), "--dir", "deeply/nested", "--json"))

      assert_equal %w[. deeply deeply/nested deeply/nested/path],
        data["directories"].map { |row| row["dir"] }
      assert_equal({ "." => true, "deeply" => true, "deeply/nested" => false, "deeply/nested/path" => false },
        data["directories"].each_with_object({}) { |row, map| map[row["dir"]] = row["ancestor"] })
    end

    test "--no-ancestors is the subtree alone" do
      data = json(okf("index", fixture("edge-cases"), "--dir", "deeply/nested", "--no-ancestors", "--json"))

      assert_equal %w[deeply/nested deeply/nested/path], data["directories"].map { |row| row["dir"] }
      assert_equal [ false, false ], data["directories"].map { |row| row["ancestor"] }
    end

    test "the chain is an ascent, so --depth never bounds it" do
      # --depth bounds how far *below* the starting point the map reaches; the
      # ancestors are how you got there. Two axes, so `--depth 0` still means
      # "the named directory alone" — plus the chain that places it.
      data = json(okf("index", fixture("edge-cases"), "--dir", "deeply/nested", "--depth", "0", "--json"))

      assert_equal %w[. deeply deeply/nested], data["directories"].map { |row| row["dir"] }
      assert_equal [ true, true, false ], data["directories"].map { |row| row["ancestor"] }
    end

    test "a directory with no ancestors gains none, and neither does an unfiltered map" do
      assert_equal [ "." ], map_dirs(okf("index", fixture("edge-cases"), "--dir", "root", "--json"))
      assert_equal [ false ], json(okf("index", fixture("edge-cases"), "--dir", "root", "--json"))["directories"].map { |row| row["ancestor"] }

      whole = json(okf("index", fixture("edge-cases"), "--json"))
      assert_equal 4, whole["count"]
      assert_equal [ false ] * 4, whole["directories"].map { |row| row["ancestor"] },
        "nothing was asked for, so nothing is context for it"
    end

    test "a --dir that names nothing gains no chain either" do
      # The chain is context for an answer. With no answer there is nothing to
      # place, and a lone root row reads as a partial result to a query that in
      # fact matched nothing.
      result = okf("index", fixture("conformant"), "--dir", "nosuchdir")

      assert_equal 0, result.status, "a filter matching nothing is still an advisory read"
      assert_equal [], json(okf("index", fixture("conformant"), "--dir", "nosuchdir", "--json"))["directories"]
      assert_equal "Index map — #{fixture("conformant")} (0 directories)\n", result.out
    end

    test "the deprecated --area gains no chain — a deprecated flag keeps its old answer" do
      result = okf("index", fixture("edge-cases"), "--area", "deeply", "--json")

      assert_equal [ "deeply" ], json(result)["directories"].map { |row| row["dir"] }
      assert_match(/--area is deprecated/, result.err)
    end

    test "the human map marks an ancestor row so context is not mistaken for the answer" do
      result = okf("index", fixture("edge-cases"), "--dir", "deeply/nested", "--no-body")

      assert_equal 0, result.status
      assert_match(/\(4 directories\)/, result.out)
      assert_match(%r{^  ↑ \(root\)  \(no index\.md\)  ·}, result.out)
      assert_match(%r{^  ↑ deeply/  \(no index\.md\)  ·}, result.out)
      assert_match(%r{^  deeply/nested/  \(no index\.md\)  ·}, result.out)
      refute_match(%r{^  ↑ deeply/nested/}, result.out)
    end

    test "a --depth that is not a whole number is a usage error (exit 2)" do
      [ "-1", "two", "1.5" ].each do |value|
        result = okf("index", fixture("edge-cases"), "--depth", value)

        assert_equal 2, result.status, "--depth #{value.inspect}"
        assert_match(/--depth takes a whole number of levels/, result.err, "--depth #{value.inspect}")
        assert_empty result.out
      end
    end

    test "--area still narrows to the named directory exactly, and warns" do
      result = okf("index", fixture("edge-cases"), "--area", "deeply", "--json")

      assert_equal "warning: --area is deprecated, use --dir\n", result.err
      assert_equal [ "deeply" ], json(result)["directories"].map { |row| row["dir"] },
        "the deprecated flag keeps its old exact-match behavior, never the new one"
      assert_empty okf("index", fixture("edge-cases"), "--dir", "deeply", "--json").err
    end

    test "an unknown --area selects nothing and stays advisory (exit 0)" do
      human = okf("index", fixture("conformant"), "--area", "nope")

      assert_equal 0, human.status
      assert_equal "Index map — #{fixture("conformant")} (0 directories)\n", human.out
      assert_equal "warning: --area is deprecated, use --dir\n", human.err

      data = json(okf("index", fixture("conformant"), "--area", "nope", "--json"))
      assert_equal 0, data["count"]
      assert_equal [], data["directories"]
    end

    test "--no-body drops the prose to a skeleton; the default keeps it" do
      default = okf("index", fixture("conformant"))
      lean = okf("index", fixture("conformant"), "--no-body")

      assert_equal 0, lean.status
      assert_match(/# Sales Knowledge/, default.out)
      refute_match(/# Sales Knowledge/, lean.out, "--no-body drops the authored body")
      assert_match(/^  datasets\/  ·  1 concept · BigQuery Dataset 1$/, lean.out, "the headings and rollups stay")
      assert_match(/^    → datasets\/  tables\/$/, lean.out, "so does the structure")
      assert_match(/^    • Orders — One row per completed customer order\.$/, lean.out,
        "a synthesized listing is not a body — it survives --no-body")
    end

    test "--no-body drops the body property from the JSON; --body puts it back" do
      lean = json(okf("index", fixture("conformant"), "--json", "--no-body"))
      full = json(okf("index", fixture("conformant"), "--json", "--body"))

      refute_includes lean["directories"].first.keys, "body"
      assert_includes lean["directories"].first.keys, "listing", "only the body goes"
      assert_match(/# Sales Knowledge/, full["directories"].first["body"])
    end

    test "--fields keeps only the named properties and implies --json" do
      result = okf("index", fixture("conformant"), "--fields", "dir,count")

      assert_equal 0, result.status
      data = json(result)
      assert_equal [ { "dir" => ".", "count" => 0 }, { "dir" => "datasets", "count" => 1 }, { "dir" => "tables", "count" => 2 } ],
        data["directories"]
      assert_equal 3, data["count"], "the envelope's own count is not projected away"
    end

    test "--except body,listing is the lean skeleton the skill documents" do
      result = okf("index", fixture("conformant"), "--except", "body,listing")

      assert_equal 0, result.status
      data = json(result)
      assert_equal %w[dir ancestor index_path present synthesized count types tags subdirs], data["directories"].first.keys
      assert_equal({ "BigQuery Table" => 2 }, data["directories"].last["types"], "the rollups are what is left")
      assert_operator result.out.bytesize, :<, okf("index", fixture("conformant"), "--json").out.bytesize / 2,
        "the skeleton costs a fraction of the full map"
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      result = okf("index", fixture("conformant"), "--fields", "dir", "--except", "body")

      assert_equal 2, result.status
      assert_match(/--fields and --except are mutually exclusive/, result.err)
      assert_empty result.out
    end

    test "a field no row carries is a usage error, in either flag (exit 2)" do
      fields = okf("index", fixture("conformant"), "--fields", "bogus")

      assert_equal 2, fields.status
      assert_match(/unknown field\(s\): bogus \(available: dir, ancestor, index_path, .*listing\)/, fields.err)
      assert_empty fields.out

      except = okf("index", fixture("conformant"), "--except", "bogus")
      assert_equal 2, except.status
      assert_match(/unknown field\(s\): bogus/, except.err)
    end

    test "index reads the reserved layer the concept views cannot see" do
      # index.md and log.md are reserved files, not concepts: `files` never lists
      # them, and the root's own count stays 0 though the bundle holds 3 concepts.
      # `index` is the only view that surfaces an authored index's prose.
      map = okf("index", fixture("conformant"))
      files = okf("files", fixture("conformant"))

      assert_match(/# Sales Knowledge/, map.out, "index reads index.md")
      refute_match(/index\.md$/, files.out)
      refute_match(/log\.md/, files.out)
      assert_match(/^  \(root\)  ·  0 concepts$/, map.out, "the root's two reserved files count as no concepts")

      # A directory that holds nothing but an index.md is still on the map — the
      # concept views have no row for it at all.
      sub = okf("index", fixture("structural"))
      assert_equal 0, sub.status
      assert_match(/^  sub\/  ·  0 concepts$/, sub.out)
      assert_match(/^    # A nested index must not carry frontmatter \(§9\.3\)$/, sub.out)
      refute_match(/sub\//, okf("files", fixture("structural")).out)
    end

    test "a malformed bundle is best-effort — skips noted on stderr, exit 0" do
      result = okf("index", fixture("malformed"))

      assert_equal 0, result.status
      assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
      assert_match(/^  \(root\)  \(no index\.md\)  ·  3 concepts/, result.out, "the files that parse still map")
      assert_match(/^    • Good — A valid concept living among malformed ones\.$/, result.out)
    end

    test "the ancestor chain survives a directory spelled with capitals" do
      result = okf("index", fixture("cased"), "--dir", "Docs/Guides", "--json")

      assert_equal 0, result.status
      assert_equal [ ".", "Docs", "Docs/Guides" ], map_dirs(result)
      chain = json(result).fetch("directories").select { |row| row["ancestor"] }
      assert_equal [ ".", "Docs" ], chain.map { |row| row["dir"] }
    end

    test "--dir accepts the trailing slash the map itself prints" do
      slashed = okf("index", fixture("conformant"), "--dir", "tables/", "--json")

      assert_equal 0, slashed.status
      assert_equal map_dirs(okf("index", fixture("conformant"), "--dir", "tables", "--json")), map_dirs(slashed)
      assert_includes map_dirs(slashed), "tables"
    end

    test "--area and --depth do not combine (exit 2)" do
      # The deprecated flag is exact and --depth is relative to a starting point
      # it never sets, so the pair used to union the area with every directory
      # at that depth — extra rows that read like an answer.
      result = okf("index", fixture("edge-cases"), "--area", "deeply", "--depth", "0")

      assert_equal 2, result.status
      assert_match(/--area and --depth/, result.err)
      assert_empty result.out
    end

    test "--area and --dir do not combine (exit 2)" do
      # One is exact and one is a prefix, so the pair used to union them: the map
      # came back with `datasets` *and* the `tables` subtree, an answer to neither
      # question. The same reasoning that refuses --area with --depth — a
      # deprecated flag that quietly widens is worse than one that is merely old.
      result = okf("index", fixture("conformant"), "--area", "datasets", "--dir", "tables")

      assert_equal 2, result.status
      assert_match(/--area and --dir/, result.err)
      assert_empty result.out
    end

    test "usage errors exit 2: missing dir, no dir, bad flag" do
      missing = okf("index", File.join(BUNDLES, "does-not-exist"))
      assert_equal 2, missing.status
      assert_match(/is not a directory/, missing.err)

      bare = okf("index")
      assert_equal 2, bare.status
      assert_match(/Usage: okf index <dir\|@slug>/, bare.err)

      bad_flag = okf("index", fixture("conformant"), "--bogus")
      assert_equal 2, bad_flag.status
      assert_match(/invalid option: --bogus/, bad_flag.err)
      assert_empty bad_flag.out
    end

    private

    def map_dirs(result)
      json(result).fetch("directories").map { |row| row["dir"] }
    end
  end
end
