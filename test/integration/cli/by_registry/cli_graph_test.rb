# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf graph` named through the registry. Like every read verb, its output names
# the bundle it describes: the human line reads `Graph — @slug (/path)`, and the
# JSON carries the same `bundle`/`slug` head over the model. Nodes and edges are
# the model itself and stay untouched by the ref — only the head knows the name.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLIGraphTest < CLIIntegrationCase
    test "@slug graphs the registered bundle" do
      with_registry("conformant") do
        result = okf("graph", "@conformant")

        assert_equal 0, result.status
        assert_match(/\AGraph — @conformant \(#{Regexp.escape(fixture("conformant"))}\) \(3 concepts, 6 links\)\n\z/, result.out)
        assert_empty result.err
      end
    end

    test "bare @ graphs the registry default" do
      with_registry("conformant", "minimal") do
        default = okf("graph", "@")

        assert_equal 0, default.status
        assert_match(/\AGraph — @conformant .* \(3 concepts, 6 links\)\n\z/, default.out,
          "bare @ resolves the default and echoes the slug it resolved to, never a bare @")
        assert_match(/\AGraph — @minimal .* \(1 concept, 0 links\)\n\z/, okf("graph", "@minimal").out,
          "and the other ref reaches the other bundle")
      end
    end

    test "a ref and its path graph the same model, differing only in the identity named" do
      with_registry("conformant") do
        by_ref = json(okf("graph", "@conformant", "--json"))
        by_path = json(okf("graph", fixture("conformant"), "--json"))

        assert_equal by_path["nodes"], by_ref["nodes"], "the model does not depend on how the bundle was named"
        assert_equal by_path["edges"], by_ref["edges"]
        assert_equal by_path["bundle"], by_ref["bundle"], "both resolve to the same directory"
        assert_equal "conformant", by_ref["slug"]
        refute by_path.key?("slug"), "a bundle named by path carries no slug — it was not asked for by that name"
      end
    end

    test "--json carries the identity head over the model, like every other view" do
      with_registry("conformant") do
        data = json(okf("graph", "@conformant", "--json"))

        assert_equal %w[bundle slug nodes edges], data.keys,
          "the head names the bundle; nodes/edges follow it, unchanged"
        assert_equal fixture("conformant"), data["bundle"], "bundle is always the directory"
        assert_equal "conformant", data["slug"], "slug is always the registry slug"
        assert_equal 3, data["nodes"].size
      end
    end

    test "--json nodes carry knowledge and no render fields, named by ref" do
      with_registry("minimal") do
        node = json(okf("graph", "@minimal", "--json"))["nodes"].first

        assert_equal %w[body description id tags title type], node.keys.sort
        assert_equal "note", node["id"]
        refute node.key?("sz"), "sz is a render concern and must not appear in the graph model"
      end
    end

    test "--minimal ships lean nodes plus the type and tag indexes, named by ref" do
      with_registry("conformant") do
        data = json(okf("graph", "@conformant", "--json", "--minimal"))

        assert_equal %w[id title], data["nodes"].first.keys.sort
        assert_equal %w[bundle slug nodes edges types tags], data.keys, "--minimal adds indexes after the head"
        assert data["types"].key?("BigQuery Table")
      end
    end

    test "--no-body keeps the metadata but drops the body, named by ref" do
      with_registry("minimal") do
        node = json(okf("graph", "@minimal", "--json", "--no-body"))["nodes"].first

        assert_equal %w[description id tags title type], node.keys.sort
        assert_operator okf("graph", "@minimal", "--json", "--no-body").out.bytesize, :<,
          okf("graph", "@minimal", "--json").out.bytesize
      end
    end

    test "--pretty implies --json and indents the same model" do
      with_registry("conformant") do
        pretty = okf("graph", "@conformant", "--pretty")

        assert_equal 0, pretty.status
        assert_equal JSON.parse(okf("graph", "@conformant", "--json").out), JSON.parse(pretty.out)
        assert_match(/\A\{\n  "bundle": ".*",\n  "slug": "conformant",\n  "nodes": \[\n/, pretty.out)
      end
    end

    test "a malformed ref-named bundle is best-effort — skips noted, exit 0" do
      with_registry("malformed") do
        result = okf("graph", "@malformed")

        assert_equal 0, result.status
        assert_match(/\AGraph — @malformed .* \(3 concepts, 0 links\)\n\z/, result.out)
        assert_match(/note: skipped 2 file\(s\) with invalid frontmatter/, result.err)
      end
    end

    test "an empty ref-named bundle yields an empty graph" do
      with_registry("empty") do
        result = okf("graph", "@empty")

        assert_equal 0, result.status
        assert_match(/\AGraph — @empty .* \(0 concepts, 0 links\)\n\z/, result.out)
      end
    end

    test "an unknown slug is a usage error naming the registry file it read" do
      with_registry("conformant") do
        result = okf("graph", "@ghost")

        assert_equal 2, result.status
        assert_match(/\Aerror: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_empty result.out
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move" do
      doomed = register_doomed

      with_registry("conformant") do
        result = okf("graph", "@doomed")

        assert_equal 2, result.status
        assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
          result.err)
        assert_empty result.out
      end
    end

    test "bare @ on an empty registry hints at registering one" do
      with_registry do
        result = okf("graph", "@")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @ in .*registry\.json \(okf registry set <dir>\)/, result.err)
      end
    end

    test "--home is not graph's to offer — refs read $OKF_HOME" do
      with_registry("conformant") do
        result = okf("graph", "@conformant", "--home", @home)

        assert_equal 2, result.status
        assert_match(/invalid option: --home/, result.err)
        assert_empty result.out
      end
    end

    test "a second bundle is a question graph cannot answer (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("graph", "@conformant", "@minimal")

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
