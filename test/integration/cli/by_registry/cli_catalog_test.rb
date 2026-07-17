# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf catalog` named through the registry — the same concept inventory the
# by_dir file proves, re-proven for the identity a registration gives: every
# flag and format reached via `@slug` or bare `@`, the header reading
# `@slug (/path)`, and the JSON carrying both `bundle` (the directory) and
# `slug` (the registry name).
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLICatalogTest < CLIIntegrationCase
    test "@slug groups concepts under their area, exactly as the path form does (exit 0)" do
      with_registry("conformant") do
        result = okf("catalog", "@conformant")

        assert_equal 0, result.status
        assert_match(/datasets\/ \(1\)/, result.out)
        assert_match(/tables\/ \(2\)/, result.out)
        assert_match(/Sales {2}·  BigQuery Dataset {2}·  ↳4/, result.out)
        assert_equal okf("catalog", fixture("conformant")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    # The heart of this folder: named by ref, the header carries the identity the
    # caller used — and the path it resolved to, so the answer is self-locating.
    test "the human header reads `@slug (/path)`" do
      with_registry("conformant") do
        assert_match(/^Catalog — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 concepts\)$/,
          okf("catalog", "@conformant").out)
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("conformant") do
        data = json(okf("catalog", "@conformant", "--json"))

        assert_equal fixture("conformant"), data.fetch("bundle"), "`bundle` is always the directory"
        assert_equal "conformant", data.fetch("slug"), "`slug` is only ever the registry slug"
        assert_equal 3, data.fetch("count")
        keys = data.fetch("concepts").first.keys.sort
        assert_equal %w[area backlog_ref description dir id links_in links_out status tags timestamp title type], keys
        assert_equal "datasets/sales", data.fetch("concepts").first.fetch("id")
      end
    end

    test "bare @ resolves the registry default, and names it by the slug it landed on" do
      with_registry("conformant", "minimal") do
        # Unchosen, the first registered bundle is the effective default.
        assert_match(/^Catalog — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 concepts\)$/, okf("catalog", "@").out)

        okf("registry", "default", "minimal")
        result = okf("catalog", "@")

        assert_equal 0, result.status
        assert_match(/^Catalog — @minimal \(#{Regexp.escape(fixture("minimal"))}\) \(1 concept\)$/, result.out,
          "bare @ follows the chosen default, and the header names `@minimal` — the slug, not the `@` typed")
        assert_equal "minimal", json(okf("catalog", "@", "--json")).fetch("slug")
      end
    end

    test "@One resolves the way registration slugified it" do
      with_registry do
        okf("registry", "set", fixture("minimal"), "--as", "One")

        result = okf("catalog", "@One")

        assert_equal 0, result.status
        assert_equal fixture("minimal"), json(okf("catalog", "@One", "--json")).fetch("bundle")
        assert_equal "one", json(okf("catalog", "@One", "--json")).fetch("slug")
        assert_match(/^Catalog — @one \(/, result.out, "the header answers with the registered slug, not the spelling asked for")
      end
    end

    test "--pretty implies --json and indents it, slug and all" do
      with_registry("minimal") do
        result = okf("catalog", "@minimal", "--pretty")

        assert_equal 1, JSON.parse(result.out).fetch("count") # implies --json
        assert_match(/^\{\n  "bundle": /, result.out)         # …and indents it
        assert_match(/^  "slug": "minimal",$/, result.out)
        assert_match(/^\{"bundle".*"slug":"minimal"/, okf("catalog", "@minimal", "--json").out) # compact without it
      end
    end

    test "--fields keeps only the named properties; the ref envelope survives the projection" do
      with_registry("conformant") do
        data = json(okf("catalog", "@conformant", "--fields", "id,title"))

        assert_equal %w[id title], data.fetch("concepts").first.keys
        assert_equal "Sales", data.fetch("concepts").first.fetch("title")
        assert_equal "conformant", data.fetch("slug"), "the projection cuts rows, never the identity envelope"
        assert_equal fixture("conformant"), data.fetch("bundle")
        assert_equal 3, data.fetch("count")
      end
    end

    test "--except drops the named properties and keeps the envelope whole" do
      with_registry("conformant") do
        data = json(okf("catalog", "@conformant", "--except", "tags,timestamp"))
        row = data.fetch("concepts").first

        refute row.key?("tags")
        refute row.key?("timestamp")
        assert_equal "datasets/sales", row.fetch("id")
        assert_equal "conformant", data.fetch("slug")
      end
    end

    test "field names match case-insensitively through a ref too" do
      with_registry("conformant") do
        assert_equal %w[id title], json(okf("catalog", "@conformant", "--fields", "ID,Title")).fetch("concepts").first.keys
      end
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      with_registry("conformant") do
        result = okf("catalog", "@conformant", "--fields", "id", "--except", "title")

        assert_equal 2, result.status
        assert_match(/mutually exclusive/, result.err)
      end
    end

    test "an unknown field is a usage error naming the valid ones (exit 2)" do
      with_registry("conformant") do
        result = okf("catalog", "@conformant", "--fields", "bogus")

        assert_equal 2, result.status
        assert_match(/unknown field\(s\): bogus/, result.err)
        assert_match(/available: id, title, type, description, tags/, result.err)
        assert_equal "", result.out
        assert_equal 2, okf("catalog", "@conformant", "--except", "nope").status # --except too
      end
    end

    test "--type selects one concept type, case-insensitively, and the header counts the narrowing" do
      with_registry("conformant") do
        result = okf("catalog", "@conformant", "--type", "BigQuery Table")

        assert_equal 0, result.status
        assert_match(/^Catalog — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(2 of 3 concepts\)$/, result.out)
        refute_match(/Sales/, result.out)

        folded = json(okf("catalog", "@conformant", "--type", "bigquery table", "--json"))
        assert_equal %w[tables/customers tables/orders], folded.fetch("concepts").map { |row| row["id"] }
        assert_equal "conformant", folded.fetch("slug"), "a filtered view keeps the identity contract"
      end
    end

    test "--area selects a top-level area, case-insensitively, and takes `root`" do
      with_registry("conformant", "edge-cases") do
        data = json(okf("catalog", "@conformant", "--area", "TABLES", "--json"))
        assert_equal 2, data.fetch("count")
        assert_equal %w[tables tables], data.fetch("concepts").map { |row| row["area"] }

        rooted = json(okf("catalog", "@edge-cases", "--area", "root", "--json"))
        assert_equal %w[links-in-fences reference-style target], rooted.fetch("concepts").map { |row| row["id"] }
        assert_equal "edge-cases", rooted.fetch("slug")
      end
    end

    test "--tag selects concepts carrying a tag, case-insensitively" do
      with_registry("conformant") do
        data = json(okf("catalog", "@conformant", "--tag", "ORDERS", "--json"))

        assert_equal 1, data.fetch("count")
        assert_equal "tables/orders", data.fetch("concepts").first.fetch("id")
      end
    end

    test "a filter composes with a projection under a ref" do
      with_registry("conformant") do
        data = json(okf("catalog", "@conformant", "--type", "BigQuery Table", "--fields", "id"))

        assert_equal [ { "id" => "tables/customers" }, { "id" => "tables/orders" } ], data.fetch("concepts")
        assert_equal "conformant", data.fetch("slug")
      end
    end

    test "a filter matching nothing is an empty list, not an error (exit 0)" do
      with_registry("conformant") do
        result = okf("catalog", "@conformant", "--tag", "nosuchtag", "--json")

        assert_equal 0, result.status
        assert_equal 0, json(result).fetch("count")
        assert_equal [], json(result).fetch("concepts")
        assert_match(/\(0 of 3 concepts\)/, okf("catalog", "@conformant", "--tag", "nosuchtag").out)
      end
    end

    test "an unknown slug is a usage error naming the registry file it consulted (exit 2)" do
      with_registry("conformant") do
        result = okf("catalog", "@nope")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @nope in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err,
          "the message names the file consulted, so an $OKF_HOME mismatch self-diagnoses")
        assert_equal "", result.out
        refute_match(/\.rb:\d+/, result.err, "a bad ref is a message, never a backtrace")
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move (exit 2)" do
      with_registry("conformant") do
        gone = register_vanished("doomed")

        result = okf("catalog", "@doomed")

        assert_equal 2, result.status
        assert_match(/^error: @doomed points to #{Regexp.escape(gone)}, which is not a directory \(okf registry del doomed, or restore it\)$/, result.err)
        assert_equal "", result.out
      end
    end

    test "bare @ against an empty registry hints `okf registry set`" do
      with_registry do
        result = okf("catalog", "@")

        assert_equal 2, result.status
        assert_match(/^error: not a registered bundle: @ in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry set <dir>\)$/, result.err,
          "with nothing registered the hint is to register, not to list")
      end
    end

    # A ref reads $OKF_HOME (or ~/.okf); catalog offers no --home to steer it —
    # only registry, server, and search do.
    test "--home is not offered: catalog steers its refs by $OKF_HOME alone (exit 2)" do
      with_registry("conformant") do
        result = okf("catalog", "@conformant", "--home", @home)

        assert_equal 2, result.status
        assert_match(/invalid option: --home/, result.err)
        assert_equal "", result.out
      end
    end

    test "a second bundle is a usage error — catalog answers about one (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("catalog", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/^error: unexpected argument '@minimal'$/, result.err)
        assert_equal "", result.out
      end
    end

    test "best-effort read through a ref: malformed files are skipped (stderr), stdout stays valid" do
      with_registry("malformed") do
        result = okf("catalog", "@malformed")
        assert_equal 0, result.status, "a bundle full of §9 errors still catalogs — this is an advisory read, never exit 1"
        assert_match(/skipped 2 file\(s\) with invalid frontmatter/, result.err)
        assert_match(/Good {2}·  Note/, result.out)

        machine = okf("catalog", "@malformed", "--json")
        assert_equal 3, json(machine).fetch("count") # the note went to stderr, so this parses
        assert_equal "malformed", json(machine).fetch("slug")
      end
    end

    test "an empty registered bundle catalogs to zero concepts, not a crash" do
      with_registry("empty") do
        result = okf("catalog", "@empty")

        assert_equal 0, result.status
        assert_match(/^Catalog — @empty \(#{Regexp.escape(fixture("empty"))}\) \(0 concepts\)$/, result.out)
        assert_equal [], json(okf("catalog", "@empty", "--json")).fetch("concepts")
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
