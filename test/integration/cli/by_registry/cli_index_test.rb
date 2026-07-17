# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf index` named through the registry — the §6 orientation map, reached by the
# identity a registry gives. Every narrowing and every projection re-proven at a
# `@slug`, and the map's own head carrying both the directory and the slug so a
# row still resolves to a file.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLIIndexTest < CLIIntegrationCase
    test "@slug maps the registered bundle and names both identities" do
      with_registry("conformant") do
        result = okf("index", "@conformant")

        assert_equal 0, result.status
        assert_match(/\AIndex map — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 directories\)$/, result.out)
        assert_match(/^  \(root\)  ·  0 concepts$/, result.out)
        assert_match(/^    → datasets\/  tables\/$/, result.out)
        assert_match(/^  tables\/  \(no index\.md\)  ·  2 concepts · BigQuery Table 2$/, result.out)
        assert_match(/^    # Sales Knowledge$/, result.out, "the authored index body still prints verbatim")
      end
    end

    test "bare @ maps the registry default under its slug" do
      with_registry("conformant", "minimal") do
        default = okf("index", "@")

        assert_equal 0, default.status
        assert_match(/\AIndex map — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 directories\)$/, default.out)
        assert_equal okf("index", "@conformant").out, default.out
      end
    end

    test "--json carries the directory and the slug, then one row per directory" do
      with_registry("conformant") do
        data = json(okf("index", "@conformant", "--json"))

        assert_equal fixture("conformant"), data["bundle"], "`bundle` is the directory — a row resolves to <dir>/<id>.md"
        assert_equal "conformant", data["slug"]
        assert_equal 3, data["count"]
        assert_equal [ ".", "datasets", "tables" ], data["directories"].map { |row| row["dir"] }
        assert_path_exists File.join(data["bundle"], "#{data["directories"].last["listing"].first["id"]}.md"),
          "the head's dir plus a listed id is a real file — the ref resolves without a second lookup"
      end
    end

    test "the same map by path carries no slug" do
      with_registry("conformant") do
        by_path = json(okf("index", fixture("conformant"), "--json"))

        assert_equal fixture("conformant"), by_path["bundle"]
        refute by_path.key?("slug")
        assert_equal json(okf("index", "@conformant", "--json"))["directories"], by_path["directories"],
          "only the identity differs — the map itself is the same"
      end
    end

    test "--pretty implies --json and indents the same map" do
      with_registry("conformant") do
        pretty = okf("index", "@conformant", "--pretty")

        assert_equal 0, pretty.status
        assert_equal JSON.parse(okf("index", "@conformant", "--json").out), JSON.parse(pretty.out)
        assert_match(/^  "slug": "conformant",$/, pretty.out)
      end
    end

    test "--area narrows a ref-named map; `root` names the bundle root" do
      with_registry("conformant") do
        tables = okf("index", "@conformant", "--area", "tables")

        assert_equal 0, tables.status
        assert_match(/\AIndex map — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(1 directory\)$/, tables.out,
          "the noun follows the count, and the identity survives the narrowing")
        refute_match(/datasets/, tables.out)

        root = okf("index", "@conformant", "--area", "root")
        assert_match(/^  \(root\)  ·  0 concepts$/, root.out)
        refute_match(/^  tables\//, root.out)
      end
    end

    test "--area is repeatable and case-insensitive through a ref" do
      with_registry("conformant") do
        data = json(okf("index", "@conformant", "--area", "TABLES", "--area", "datasets", "--json"))

        assert_equal "conformant", data["slug"]
        assert_equal 2, data["count"]
        assert_equal %w[datasets tables], data["directories"].map { |row| row["dir"] }
      end
    end

    test "an unknown --area selects nothing and stays advisory (exit 0)" do
      with_registry("conformant") do
        human = okf("index", "@conformant", "--area", "nope")

        assert_equal 0, human.status
        assert_equal "Index map — @conformant (#{fixture("conformant")}) (0 directories)\n", human.out,
          "an empty map still says which bundle came up empty"
        assert_empty human.err
      end
    end

    test "--no-body drops the prose to a skeleton, in both output forms" do
      with_registry("conformant") do
        lean = okf("index", "@conformant", "--no-body")

        assert_equal 0, lean.status
        refute_match(/# Sales Knowledge/, lean.out)
        assert_match(/^  datasets\/  ·  1 concept · BigQuery Dataset 1$/, lean.out, "the rollups stay")
        assert_match(/^    • Orders — One row per completed customer order\.$/, lean.out,
          "a synthesized listing is not a body — it survives --no-body")

        json_lean = json(okf("index", "@conformant", "--json", "--no-body"))
        refute_includes json_lean["directories"].first.keys, "body"
        assert_equal "conformant", json_lean["slug"], "the identity is head, not row — a projection never drops it"
        assert_match(/# Sales Knowledge/, json(okf("index", "@conformant", "--json", "--body"))["directories"].first["body"])
      end
    end

    test "--fields keeps only the named properties and implies --json" do
      with_registry("conformant") do
        result = okf("index", "@conformant", "--fields", "dir,count")

        assert_equal 0, result.status
        data = json(result)
        assert_equal [ { "dir" => ".", "count" => 0 }, { "dir" => "datasets", "count" => 1 }, { "dir" => "tables", "count" => 2 } ],
          data["directories"]
        assert_equal "conformant", data["slug"], "--fields projects the rows, never the head"
        assert_equal 3, data["count"], "the envelope's own count is not projected away"
      end
    end

    test "--except is the complement, and the ref's identity rides through it" do
      with_registry("conformant") do
        result = okf("index", "@conformant", "--except", "body,listing")

        assert_equal 0, result.status
        data = json(result)
        assert_equal %w[dir index_path present synthesized count types tags subdirs], data["directories"].first.keys
        assert_equal fixture("conformant"), data["bundle"]
        assert_equal "conformant", data["slug"]
        assert_operator result.out.bytesize, :<, okf("index", "@conformant", "--json").out.bytesize / 2,
          "the skeleton costs a fraction of the full map"
      end
    end

    test "--fields and --except are mutually exclusive (exit 2)" do
      with_registry("conformant") do
        result = okf("index", "@conformant", "--fields", "dir", "--except", "body")

        assert_equal 2, result.status
        assert_match(/error: --fields and --except are mutually exclusive/, result.err)
        assert_empty result.out
      end
    end

    test "a field no row carries is a usage error, in either flag (exit 2)" do
      with_registry("conformant") do
        fields = okf("index", "@conformant", "--fields", "bogus")
        assert_equal 2, fields.status
        assert_match(/error: unknown field\(s\): bogus \(available: dir, index_path, .*listing\)/, fields.err)
        assert_empty fields.out

        assert_equal 2, okf("index", "@conformant", "--except", "bogus").status
      end
    end

    test "a malformed ref-named bundle is best-effort — skips noted, exit 0" do
      with_registry("malformed") do
        result = okf("index", "@malformed")

        assert_equal 0, result.status
        assert_match(/note: skipped 2 file\(s\) with invalid frontmatter/, result.err)
        assert_match(/\AIndex map — @malformed \(#{Regexp.escape(fixture("malformed"))}\) \(1 directory\)$/, result.out)
        assert_match(/^    • Good — A valid concept living among malformed ones\.$/, result.out)
      end
    end

    test "an unknown slug is a usage error naming the registry file it read" do
      with_registry("conformant") do
        result = okf("index", "@ghost")

        assert_equal 2, result.status
        assert_match(/\Aerror: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_empty result.out
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move" do
      doomed = register_doomed

      with_registry("conformant") do
        result = okf("index", "@doomed")

        assert_equal 2, result.status
        assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
          result.err)
        assert_empty result.out
      end
    end

    test "bare @ on an empty registry hints at registering one" do
      with_registry do
        result = okf("index", "@")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @ in .*registry\.json \(okf registry set <dir>\)/, result.err)
      end
    end

    test "--home is not index's to offer — refs read $OKF_HOME" do
      with_registry("conformant") do
        result = okf("index", "@conformant", "--home", @home)

        assert_equal 2, result.status
        assert_match(/invalid option: --home/, result.err)
        assert_empty result.out
      end
    end

    test "a second bundle is a question index cannot answer (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("index", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/error: unexpected argument '@minimal'/, result.err)
        assert_empty result.out
      end
    end

    private

    # A registered bundle whose directory is then deleted — the stale entry every
    # ref-taking verb must refuse rather than half-answer. Returns its path.
    def register_doomed
      dir = File.join(@out_dir, "doomed")
      FileUtils.cp_r(fixture("minimal"), dir)
      okf("registry", "set", dir, "--as", "doomed", "--home", @home)
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
