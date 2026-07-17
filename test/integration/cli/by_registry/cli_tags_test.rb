# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf tags` named through the registry — the tag vocabulary as an inverted
# index, re-proven for the @ref identity: the flat view and both `--by`
# regroupings reached via `@slug` or bare `@`, each header reading
# `@slug (/path)` and each JSON carrying both `bundle` and `slug`.
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLITagsTest < CLIIntegrationCase
    test "@slug lists tags by count with the concepts carrying each (exit 0)" do
      with_registry("conformant") do
        result = okf("tags", "@conformant")

        assert_equal 0, result.status
        assert_match(/sales\s+3\s+Sales, Customers, Orders/, result.out)
        assert_match(/orders\s+1\s+Orders/, result.out)
        assert_operator result.out.index("sales"), :<, result.out.index("orders") # ordered by count
        assert_equal okf("tags", fixture("conformant")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    test "the human header reads `@slug (/path)`" do
      with_registry("conformant") do
        assert_match(/^Tags — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 distinct\)$/, okf("tags", "@conformant").out)
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("conformant") do
        data = json(okf("tags", "@conformant", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle"), "`bundle` is always the directory"
        assert_equal "conformant", data.fetch("slug"), "`slug` is only ever the registry slug"
        assert_equal 2, data.fetch("count")
        rows = data.fetch("tags")
        assert_equal %w[concepts count tag], rows.first.keys.sort
        assert_equal "sales", rows.first.fetch("tag")
        assert_equal %w[datasets/sales tables/customers tables/orders], rows.first.fetch("concepts")
      end
    end

    test "bare @ resolves the registry default, and names it by the slug it landed on" do
      with_registry("conformant", "minimal") do
        assert_match(/^Tags — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 distinct\)$/, okf("tags", "@").out)

        okf("registry", "default", "minimal")
        result = okf("tags", "@")

        assert_equal 0, result.status
        assert_match(/^Tags — @minimal \(#{Regexp.escape(fixture("minimal"))}\) \(0 distinct\)$/, result.out,
          "bare @ follows the chosen default, and the header names the slug it resolved to")
        assert_equal "minimal", json(okf("tags", "@", "--json")).fetch("slug")
      end
    end

    test "@One resolves the way registration slugified it" do
      with_registry do
        okf("registry", "set", fixture("conformant"), "--as", "One")

        data = json(okf("tags", "@One", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle")
        assert_equal "one", data.fetch("slug")
        assert_match(/^Tags — @one \(/, okf("tags", "@One").out, "the header answers with the registered slug, not the spelling asked for")
      end
    end

    test "--pretty implies --json and indents it, slug and all" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--pretty")

        assert_equal 2, JSON.parse(result.out).fetch("count") # still JSON, no --json needed
        assert_match(/^  "slug": "conformant",$/, result.out)
        assert_match(/^  "count": 2,$/, result.out)
        assert_match(/^  "tags": \[$/, result.out)
        refute_match(/^  "count"/, okf("tags", "@conformant", "--json").out) # compact by default
      end
    end

    test "--by type groups the tags per concept type, keeping the ref header" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--by", "type")

        assert_equal 0, result.status
        assert_match(/^Tags — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 distinct, by type\)$/, result.out)
        assert_match(/BigQuery Dataset \(1 tag\)\n\s+sales\s+1\s+Sales\n/, result.out)
        assert_match(/BigQuery Table \(2 tags\)/, result.out)
        assert_match(/sales\s+2\s+Customers, Orders/, result.out) # `sales` is connective — counted per group
      end
    end

    test "--by area groups the tags per top-level area, keeping the ref header" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--by", "area")

        assert_equal 0, result.status
        assert_match(/^Tags — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 distinct, by area\)$/, result.out)
        assert_match(%r{datasets/ \(1 tag\)\n\s+sales\s+1\s+Sales\n}, result.out)
        assert_match(%r{tables/ \(2 tags\)}, result.out)
        assert_operator result.out.index("datasets/"), :<, result.out.index("tables/") # groups sort by name
      end
    end

    test "--by type --json gains a `by` key and nests the rows under `groups`, envelope intact" do
      with_registry("conformant") do
        data = json(okf("tags", "@conformant", "--by", "type", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle")
        assert_equal "conformant", data.fetch("slug"), "the grouped view keeps the same identity contract"
        assert_equal "type", data.fetch("by")
        assert_equal 2, data.fetch("count") # distinct tags across the groups, not a group count
        groups = data.fetch("groups")
        assert_equal [ "BigQuery Dataset", "BigQuery Table" ], groups.map { |g| g.fetch("type") }
        assert_equal %w[count tags type], groups.first.keys.sort
        assert_equal [ { "tag" => "sales", "count" => 1, "concepts" => [ "datasets/sales" ] } ], groups.first.fetch("tags")
      end
    end

    test "--by area --json keys each group by its area, and names the root bare" do
      with_registry("conformant", "rooted") do
        data = json(okf("tags", "@conformant", "--by", "area", "--json"))
        assert_equal "area", data.fetch("by")
        assert_equal %w[datasets tables], data.fetch("groups").map { |g| g.fetch("area") }
        assert_equal "conformant", data.fetch("slug")

        # `rooted` is the fixture with a *tagged* root-level concept — the one
        # label printed without a trailing slash.
        rooted = json(okf("tags", "@rooted", "--by", "area", "--json"))
        assert_equal [ "(root)", "services" ], rooted.fetch("groups").map { |g| g.fetch("area") }
        assert_equal "rooted", rooted.fetch("slug")
        assert_match(/^\s{2}\(root\) \(2 tags\)$/, okf("tags", "@rooted", "--by", "area").out, "the root area is named, and never as `(root)/`")
        refute_match(%r{\(root\)/}, okf("tags", "@rooted", "--by", "area").out)
      end
    end

    test "an unknown --by dimension is a usage error (exit 2)" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--by", "colour")

        assert_equal 2, result.status
        assert_match(/invalid argument: --by colour/, result.err)
        assert_equal "", result.out
      end
    end

    test "--type narrows the concepts before the index is cut" do
      with_registry("conformant") do
        data = json(okf("tags", "@conformant", "--type", "BigQuery Table", "--json"))

        assert_equal 2, data.fetch("tags").first.fetch("count") # `sales` drops the dataset concept
        assert_equal %w[tables/customers tables/orders], data.fetch("tags").first.fetch("concepts")
        assert_equal "conformant", data.fetch("slug"), "a filtered view keeps the identity contract"
      end
    end

    test "--area narrows too, and both filters fold case" do
      with_registry("conformant") do
        data = json(okf("tags", "@conformant", "--area", "TABLES", "--json"))

        assert_equal %w[sales orders], data.fetch("tags").map { |row| row.fetch("tag") }
        assert_equal 2, data.fetch("tags").first.fetch("count")
        assert_equal 1, json(okf("tags", "@conformant", "--type", "bigquery dataset", "--json")).fetch("count")
      end
    end

    test "the filters compose with --by under a ref" do
      with_registry("conformant") do
        data = json(okf("tags", "@conformant", "--type", "BigQuery Dataset", "--by", "area", "--json"))

        assert_equal [ "datasets" ], data.fetch("groups").map { |g| g.fetch("area") } # tables/ narrowed away
        assert_equal 1, data.fetch("count")
        assert_equal "conformant", data.fetch("slug")
      end
    end

    test "a filter that matches nothing empties the index rather than failing (exit 0)" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--type", "Nope", "--json")

        assert_equal 0, result.status
        assert_equal 0, json(result).fetch("count")
        assert_equal [], json(result).fetch("tags")
      end
    end

    test "--tag is not offered — tags takes only the dimensions orthogonal to it (exit 2)" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--tag", "sales")

        assert_equal 2, result.status
        assert_match(/invalid option: --tag/, result.err)
      end
    end

    test "--fields is not offered — the tag index is not a projected list view (exit 2)" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--fields", "tag")

        assert_equal 2, result.status
        assert_match(/invalid option: --fields/, result.err)
        assert_equal "", result.out
      end
    end

    test "an unknown slug is a usage error naming the registry file it consulted (exit 2)" do
      with_registry("conformant") do
        result = okf("tags", "@nope")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @nope in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_equal "", result.out
        refute_match(/\.rb:\d+/, result.err, "a bad ref is a message, never a backtrace")
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move (exit 2)" do
      with_registry("conformant") do
        gone = register_vanished("doomed")

        result = okf("tags", "@doomed", "--by", "type")

        assert_equal 2, result.status
        assert_match(/^error: @doomed points to #{Regexp.escape(gone)}, which is not a directory \(okf registry del doomed, or restore it\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "bare @ against an empty registry hints `okf registry set`" do
      with_registry do
        result = okf("tags", "@")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)$/, result.err)
      end
    end

    test "--home is not offered: tags steers its refs by $OKF_HOME alone (exit 2)" do
      with_registry("conformant") do
        result = okf("tags", "@conformant", "--home", @home)

        assert_equal 2, result.status
        assert_match(/invalid option: --home/, result.err)
        assert_equal "", result.out
      end
    end

    test "a second bundle is a usage error — tags answers about one (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("tags", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/^error: unexpected argument '@minimal'$/, result.err)
        assert_equal "", result.out
      end
    end

    test "an untagged or empty registered bundle reports zero distinct, not an error" do
      with_registry("empty", "minimal") do
        empty = okf("tags", "@empty")
        assert_equal 0, empty.status
        assert_match(/^Tags — @empty \(#{Regexp.escape(fixture("empty"))}\) \(0 distinct\)$/, empty.out)

        untagged = okf("tags", "@minimal") # one concept, no tags key
        assert_equal 0, untagged.status
        assert_match(/\(0 distinct\)/, untagged.out)
        assert_equal [], json(okf("tags", "@minimal", "--json")).fetch("tags")
        assert_equal [], json(okf("tags", "@minimal", "--by", "type", "--json")).fetch("groups")
      end
    end

    test "best-effort read through a ref: malformed files are skipped (stderr), stdout stays parseable JSON" do
      with_registry("malformed") do
        result = okf("tags", "@malformed", "--json")

        assert_equal 0, result.status, "a bundle full of §9 errors still indexes — this is an advisory read, never exit 1"
        assert_match(/skipped 2 file\(s\) with invalid frontmatter/, result.err)
        assert_equal 0, json(result).fetch("count") # the note went to stderr, not into stdout
        assert_equal "malformed", json(result).fetch("slug")
        refute_match(/note:/, result.out)
      end
    end

    private

    # Register a scratch bundle, then delete its directory: the "registered but
    # gone" ref no committed fixture can carry (a fixture is always on disk).
    # Returns the path that went away.
    def register_vanished(slug)
      dir = File.join(@out_dir, slug)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "note.md"), "---\ntype: Note\ntitle: Doomed\n---\n\nA concept about to lose its directory.\n")
      okf("registry", "set", dir, "--home", @home)
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
