# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf search` at a single `@ref`. Search is the one verb whose envelope *switches*
# on the identity form: a leading @ puts it in registry mode, so even one ref
# answers with `bundles: [{slug, dir}]` and rows that carry their own `slug` —
# not the `bundle`/`slug` head every other read verb prints. Every flag re-proven
# through that envelope.
#
# One ref only: @all and several refs are the multi-bundle surface, tested where
# multi-bundle behavior lives.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLISearchTest < CLIIntegrationCase
    test "@slug searches the registered bundle and answers in the name that was typed" do
      with_registry("conformant") do
        result = okf("search", "@conformant", "orders")

        assert_equal 0, result.status
        assert_match(/\ASearch — @conformant · orders \(3 concepts\)$/, result.out)
        assert_match(/@conformant\s+tables\/orders\s+Orders\s+·\s+BigQuery Table\s+·\s+title\+id\+tags/, result.out,
          "even one ref labels its rows — registry mode is the form, not the count")
      end
    end

    test "one ref is still registry mode: the envelope is bundles + slugged rows" do
      with_registry("conformant") do
        data = json(okf("search", "@conformant", "orders", "--json"))

        assert_equal [ "conformant" ], data["bundles"].map { |bundle| bundle["slug"] }
        assert_equal fixture("conformant"), data["bundles"].first["dir"]
        refute data.key?("bundle"), "registry mode heads the payload with `bundles`, not the single-bundle `bundle`/`slug` pair"
        refute data.key?("slug")

        assert_equal [ "orders" ], data["query"]
        assert_equal "conformant", data["matches"].first["slug"], "every row carries the bundle it came from"
        assert_path_exists File.join(data["bundles"].first["dir"], "#{data["matches"].first["id"]}.md"),
          "the head maps slug to dir, so a row resolves to a file with no second call"
      end
    end

    test "the same bundle by path keeps the classic single-bundle envelope" do
      with_registry("conformant") do
        by_path = json(okf("search", fixture("conformant"), "orders", "--json"))

        assert_equal fixture("conformant"), by_path["bundle"]
        refute by_path.key?("bundles"), "a plain dir never enters registry mode"
        refute by_path["matches"].first.key?("slug"), "and its rows have no bundle to name"
        assert_match(/\ASearch — #{Regexp.escape(fixture("conformant"))} · orders/, okf("search", fixture("conformant"), "orders").out)
      end
    end

    test "bare @ searches the registry default and echoes the slug it resolved to" do
      with_registry("conformant", "minimal") do
        default = okf("search", "@", "orders")

        assert_equal 0, default.status
        assert_match(/\ASearch — @conformant · orders \(3 concepts\)$/, default.out,
          "the header names the bundle bare @ landed on, not the `@` that was typed")
        assert_equal okf("search", "@conformant", "orders").out, default.out

        assert_equal [ "conformant" ], json(okf("search", "@", "orders", "--json"))["bundles"].map { |b| b["slug"] }
      end
    end

    test "terms AND together through a ref, and zero matches stays advisory" do
      with_registry("conformant") do
        assert_equal 3, json(okf("search", "@conformant", "sales", "--json"))["count"]
        narrowed = json(okf("search", "@conformant", "sales", "customer_id", "--json"))
        assert_equal [ "tables/orders" ], narrowed["matches"].map { |row| row["id"] }

        none = okf("search", "@conformant", "orders", "nothing-says-this")
        assert_equal 0, none.status, "an advisory read exits 0 even with nothing to show"
        assert_match(/\ASearch — @conformant · orders nothing-says-this \(0 of 3 concepts\)$/, none.out)
        assert_match(/no matches — .*scan `okf tags @<slug>` for a bundle's vocabulary/, none.out,
          "registry mode's empty hint points back at a ref, not a path")
      end
    end

    test "--pretty implies --json and indents the registry envelope" do
      with_registry("conformant") do
        pretty = okf("search", "@conformant", "orders", "--pretty")

        assert_equal 0, pretty.status
        assert_equal JSON.parse(okf("search", "@conformant", "orders", "--json").out), JSON.parse(pretty.out)
        assert_match(/^  "bundles": \[$/, pretty.out)
      end
    end

    test "-e treats terms as regexps through a ref; an invalid pattern is a usage error" do
      with_registry("conformant") do
        hit = okf("search", "@conformant", "-e", "ord[a-z]+s")
        assert_equal 0, hit.status
        assert_match(%r{@conformant\s+tables/orders}, hit.out)

        bad = okf("search", "@conformant", "-e", "[unclosed")
        assert_equal 2, bad.status
        assert_match(/error: invalid pattern: premature end of char-class/, bad.err)
        assert_empty bad.out, "a usage error leaves stdout clean"
      end
    end

    test "the engine follows the query through a ref, and is never announced" do
      # Same routing as by_dir, proven again here because the identity is where
      # the CLI decides what to answer about: a ref takes a different path to the
      # bundle, and a verb that routes correctly by path can still be broken by ref.
      with_registry("conformant") do
        scanned = json(okf("search", "@conformant", "-e", "orders", "--json"))["matches"].first
        assert_equal weight_sum(scanned["matched"]), scanned["score"], "-e routes to the scan"

        ranked = json(okf("search", "@conformant", "orders", "--json"))["matches"].first
        refute_equal weight_sum(ranked["matched"]), ranked["score"], "the default engine ranks by BM25+"

        human = okf("search", "@conformant", "-e", "orders")
        assert_empty human.err, "choosing an engine is not a diagnostic"
        assert_equal okf("search", "@conformant", "orders").out.lines.first, human.out.lines.first,
          "the header echoes the ref that was typed — never the engine that answered"
      end
    end

    test "--fuzzy forgives a typo through a ref, and refuses to pair with -e" do
      with_registry("conformant") do
        exact = okf("search", "@conformant", "custommer", "--json")
        assert_equal 0, json(exact)["count"], "search is exact by default, so a typo misses"

        fuzzy = json(okf("search", "@conformant", "custommer", "--fuzzy", "--json"))
        assert_includes fuzzy["matches"].map { |row| row["id"] }, "tables/customers"

        # Two query languages, not two dials: a pattern is matched literally, so
        # honouring one flag and dropping the other would answer a different
        # question than the one that was asked.
        clash = okf("search", "@conformant", "custommer", "--fuzzy", "-e")
        assert_equal 2, clash.status
        assert_match(/error: --regexp and --fuzzy are mutually exclusive/, clash.err)
        assert_empty clash.out, "a usage error leaves stdout clean"
      end
    end

    test "--in narrows the searched fields; an unknown field lists the real ones" do
      with_registry("conformant") do
        scoped = okf("search", "@conformant", "orders", "--in", "title")

        assert_equal 0, scoped.status
        assert_match(/\ASearch — @conformant · orders \(1 of 3 concepts\)$/, scoped.out)
        assert_match(/@conformant\s+tables\/orders\s+Orders\s+·\s+BigQuery Table\s+·\s+title$/, scoped.out,
          "only the title hit is credited when the search is scoped to it")

        bogus = okf("search", "@conformant", "orders", "--in", "bogus")
        assert_equal 2, bogus.status
        assert_match(/error: unknown field\(s\): bogus \(searchable: title, id, tags, type, description, body\)/, bogus.err)
      end
    end

    test "the shared filters narrow a ref's candidates first" do
      with_registry("conformant") do
        scoped = json(okf("search", "@conformant", "orders", "--area", "tables", "--json"))
        assert_equal %w[tables/customers tables/orders], scoped["matches"].map { |row| row["id"] }.sort
        assert_equal [ "conformant" ], scoped["matches"].map { |row| row["slug"] }.uniq, "a filtered row still names its bundle"

        typed = json(okf("search", "@conformant", "orders", "--type", "BigQuery Dataset", "--json"))
        assert_equal [ "datasets/sales" ], typed["matches"].map { |row| row["id"] }

        tagged = json(okf("search", "@conformant", "orders", "--tag", "orders", "--json"))
        assert_equal [ "tables/orders" ], tagged["matches"].map { |row| row["id"] }

        none = okf("search", "@conformant", "orders", "--tag", "nothing-carries-this", "--json")
        assert_equal 0, none.status, "a filter matching nothing is still an advisory read"
        assert_equal 0, json(none)["count"]
        assert_equal [ "conformant" ], json(none)["bundles"].map { |bundle| bundle["slug"] },
          "the bundle was searched even though it yielded nothing"
      end
    end

    test "--fields projects the rows, --except is its complement, and they conflict" do
      with_registry("conformant") do
        lean = json(okf("search", "@conformant", "orders", "--fields", "id,score"))
        assert_equal %w[id score], lean["matches"].first.keys.sort, "--fields implies --json and keeps only what was asked"
        assert_equal [ "conformant" ], lean["bundles"].map { |bundle| bundle["slug"] },
          "the head is not a row — a projection never strips the identity"

        trimmed = json(okf("search", "@conformant", "orders", "--except", "snippet"))
        refute trimmed["matches"].first.key?("snippet")
        assert trimmed["matches"].first.key?("slug"), "--except snippet keeps the row's bundle"

        clash = okf("search", "@conformant", "orders", "--fields", "id", "--except", "score")
        assert_equal 2, clash.status
        assert_match(/error: --fields and --except are mutually exclusive/, clash.err)
      end
    end

    test "an unknown slug fails hard, names the registry, and offers the literal-term reading" do
      with_registry("conformant") do
        result = okf("search", "@ghost", "orders")

        assert_equal 2, result.status
        assert_match(/error: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)/, result.err)
        assert_match(/note: searching for a literal @-term\? put a non-@ term first, or use -e '\\@term'/, result.err,
          "an unknown slug is the one ref failure that might be a mistyped term")
        assert_empty result.out
      end
    end

    test "a registered-but-gone directory is a usage error, with no term-reading note" do
      doomed = register_doomed

      with_registry("conformant") do
        result = okf("search", "@doomed", "note")

        assert_equal 2, result.status
        assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
          result.err)
        refute_match(/literal @-term/, result.err, "a gone directory has nothing to do with the grammar")
        assert_empty result.out
      end
    end

    test "bare @ on an empty registry hints at registering one" do
      with_registry do
        result = okf("search", "@", "orders")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @ in .*registry\.json \(okf registry set <dir>\)/, result.err)
        assert_empty result.out
      end
    end

    test "a ref with no terms is a usage error showing the banner" do
      with_registry("conformant") do
        result = okf("search", "@conformant")

        assert_equal 2, result.status
        assert_match(/Usage: okf search <dir\|@slug…\|@all> <term> \[term \.\.\.\]/, result.err)
        assert_empty result.out
      end
    end

    test "a malformed ref-named bundle is best-effort — skips noted, exit 0" do
      with_registry("malformed") do
        result = okf("search", "@malformed", "valid")

        assert_equal 0, result.status
        assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
        assert_match(/@malformed\s+good\s+Good/, result.out, "the files that parse are still searched")
      end
    end

    private

    # A registered bundle whose directory is then deleted — the stale entry every
    # ref-taking verb must refuse rather than half-answer. Returns its path.
    def register_doomed
      dir = File.join(@out_dir, "doomed")
      FileUtils.cp_r(fixture("minimal"), dir)
      okf("registry", "set", dir, "--as", "doomed")
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
