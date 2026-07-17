# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf types` named through the registry — the concept-type vocabulary as an
# inverted index, re-proven for the @ref identity. The same back half as `tags`
# cut on the other axis, so it takes the filters orthogonal to it (--area,
# --tag, never --type), each reached here via `@slug` or bare `@`.
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLITypesTest < CLIIntegrationCase
    test "@slug lists types by count with the concepts of each (exit 0)" do
      with_registry("conformant") do
        result = okf("types", "@conformant")

        assert_equal 0, result.status
        assert_match(/BigQuery Table\s+2\s+Customers, Orders/, result.out)
        assert_match(/BigQuery Dataset\s+1\s+Sales/, result.out)
        assert_equal okf("types", fixture("conformant")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    test "the human header reads `@slug (/path)`" do
      with_registry("conformant") do
        assert_match(/^Types — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 distinct\)$/, okf("types", "@conformant").out)
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("conformant") do
        data = json(okf("types", "@conformant", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle"), "`bundle` is always the directory"
        assert_equal "conformant", data.fetch("slug"), "`slug` is only ever the registry slug"
        assert_equal 2, data.fetch("count")
        rows = data.fetch("types")
        assert_equal %w[concepts count type], rows.first.keys.sort
        assert_equal "BigQuery Table", rows.first.fetch("type")
        assert_equal %w[tables/customers tables/orders], rows.first.fetch("concepts")
        assert_equal [ "datasets/sales" ], rows.last.fetch("concepts")
      end
    end

    test "bare @ resolves the registry default, and names it by the slug it landed on" do
      with_registry("conformant", "minimal") do
        assert_match(/^Types — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 distinct\)$/, okf("types", "@").out)

        okf("registry", "default", "minimal")
        result = okf("types", "@")

        assert_equal 0, result.status
        assert_match(/^Types — @minimal \(#{Regexp.escape(fixture("minimal"))}\) \(1 distinct\)$/, result.out,
          "bare @ follows the chosen default, and the header names the slug it resolved to")
        assert_equal "minimal", json(okf("types", "@", "--json")).fetch("slug")
        assert_equal "Note", json(okf("types", "@", "--json")).fetch("types").first.fetch("type")
      end
    end

    test "@One resolves the way registration slugified it" do
      with_registry do
        okf("registry", "set", fixture("conformant"), "--as", "One")

        data = json(okf("types", "@One", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle")
        assert_equal "one", data.fetch("slug")
        assert_match(/^Types — @one \(/, okf("types", "@One").out, "the header answers with the registered slug, not the spelling asked for")
      end
    end

    test "--pretty implies --json and indents it, slug and all" do
      with_registry("minimal") do
        result = okf("types", "@minimal", "--pretty")

        assert_equal 1, JSON.parse(result.out).fetch("count") # still JSON, no --json needed
        assert_match(/^  "slug": "minimal",$/, result.out)
        assert_match(/^  "count": 1,$/, result.out)
        assert_match(/^      "type": "Note",$/, result.out)
        refute_match(/\n  "count"/, okf("types", "@minimal", "--json").out) # compact by default
      end
    end

    test "rows order by count, ties by name" do
      with_registry("conformant", "rooted") do
        busiest = json(okf("types", "@conformant", "--json")).fetch("types")
        assert_equal [ "BigQuery Table", "BigQuery Dataset" ], busiest.map { |row| row.fetch("type") }
        assert_equal [ 2, 1 ], busiest.map { |row| row.fetch("count") }

        # rooted carries two types at count 1 apiece — the tie breaks by name
        tied = json(okf("types", "@rooted", "--json")).fetch("types")
        assert_equal [ 1, 1 ], tied.map { |row| row.fetch("count") }
        assert_equal %w[Decision Service], tied.map { |row| row.fetch("type") }
      end
    end

    test "--area narrows to one top-level area, `root` naming the bundle root" do
      with_registry("conformant", "edge-cases") do
        tables = json(okf("types", "@conformant", "--area", "tables", "--json"))
        assert_equal 1, tables.fetch("count") # BigQuery Dataset lives in datasets/, and drops
        assert_equal "BigQuery Table", tables.fetch("types").first.fetch("type")
        assert_equal 2, tables.fetch("types").first.fetch("count")
        assert_equal "conformant", tables.fetch("slug"), "a filtered view keeps the identity contract"

        rooted = json(okf("types", "@edge-cases", "--area", "root", "--json"))
        assert_equal %w[links-in-fences reference-style target], rooted.fetch("types").first.fetch("concepts")
        assert_equal "edge-cases", rooted.fetch("slug")
      end
    end

    test "--tag narrows to the concepts carrying a tag" do
      with_registry("conformant") do
        data = json(okf("types", "@conformant", "--tag", "orders", "--json"))

        assert_equal 1, data.fetch("count")
        assert_equal [ "tables/orders" ], data.fetch("types").first.fetch("concepts")
        assert_equal 1, data.fetch("types").first.fetch("count") # counted after the narrowing
        assert_equal "conformant", data.fetch("slug")
      end
    end

    test "the filters fold case, and one matching nothing empties the index (exit 0)" do
      with_registry("conformant") do
        assert_equal 2, json(okf("types", "@conformant", "--area", "TABLES", "--json")).fetch("types").first.fetch("count")
        assert_equal 2, json(okf("types", "@conformant", "--tag", "SALES", "--json")).fetch("count")

        result = okf("types", "@conformant", "--tag", "nope", "--json")
        assert_equal 0, result.status
        assert_equal [], json(result).fetch("types")
      end
    end

    test "--type is not offered — types takes only the dimensions orthogonal to it (exit 2)" do
      with_registry("conformant") do
        result = okf("types", "@conformant", "--type", "BigQuery Table")

        assert_equal 2, result.status
        assert_match(/invalid option: --type/, result.err)
        assert_equal "", result.out
      end
    end

    test "--fields is not offered — the type index is not a projected list view (exit 2)" do
      with_registry("conformant") do
        result = okf("types", "@conformant", "--fields", "type")

        assert_equal 2, result.status
        assert_match(/invalid option: --fields/, result.err)
        assert_equal "", result.out
      end
    end

    test "an unknown slug is a usage error naming the registry file it consulted (exit 2)" do
      with_registry("conformant") do
        result = okf("types", "@nope")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @nope in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_equal "", result.out
        refute_match(/\.rb:\d+/, result.err, "a bad ref is a message, never a backtrace")
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move (exit 2)" do
      with_registry("conformant") do
        gone = register_vanished("doomed")

        result = okf("types", "@doomed")

        assert_equal 2, result.status
        assert_match(/^error: @doomed points to #{Regexp.escape(gone)}, which is not a directory \(okf registry del doomed, or restore it\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "bare @ against an empty registry hints `okf registry set`" do
      with_registry do
        result = okf("types", "@")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)$/, result.err)
      end
    end

    test "a second bundle is a usage error — types answers about one (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("types", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/^error: unexpected argument '@minimal'$/, result.err)
        assert_equal "", result.out
      end
    end

    test "an empty registered bundle reports zero distinct, not an error" do
      with_registry("empty") do
        result = okf("types", "@empty")

        assert_equal 0, result.status
        assert_match(/^Types — @empty \(#{Regexp.escape(fixture("empty"))}\) \(0 distinct\)$/, result.out)
        assert_equal [], json(okf("types", "@empty", "--json")).fetch("types")
      end
    end

    test "best-effort read through a ref: malformed files are skipped (stderr), stdout stays parseable JSON" do
      with_registry("malformed") do
        result = okf("types", "@malformed", "--json")

        assert_equal 0, result.status, "a bundle full of §9 errors still indexes — this is an advisory read, never exit 1"
        assert_match(/skipped 2 unusable file\(s\)/, result.err)
        assert_equal 2, json(result).fetch("count") # Note, plus the one Untyped bucket the unusable types share
        assert_equal [ "good" ], json(result).fetch("types").find { |row| row.fetch("type") == "Note" }.fetch("concepts")
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
      okf("registry", "set", dir)
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
