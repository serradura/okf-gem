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

    test "@slug --hubs keeps the identity head over the ranking" do
      with_registry("shapely") do
        result = okf("graph", "@shapely", "--hubs")

        assert_equal 0, result.status
        assert_match(/\AHubs — @shapely \(#{Regexp.escape(fixture("shapely"))}\) \(2 of 4 concepts with inbound links\)\n/, result.out)

        data = json(okf("graph", "@shapely", "--hubs", "--json"))
        assert_equal "shapely", data.fetch("slug")
        assert_equal fixture("shapely"), data.fetch("bundle")
        assert_equal "core/status", data.fetch("hubs").first.fetch("id")
      end
    end

    test "@slug --traffic keeps the identity head over the reduction" do
      with_registry("shapely") do
        result = okf("graph", "@shapely", "--traffic")

        assert_equal 0, result.status
        assert_match(/\ATraffic — @shapely \(#{Regexp.escape(fixture("shapely"))}\) \(4 dirs, 2 arcs at weight 1 or more\)\n/, result.out)
        assert_match(/^  flows           2         1     2     0       33%$/, result.out, "the cohesion evidence rides along")
      end
    end

    test "bare @ reports traffic for the registry default, and --json carries slug and path like every view" do
      with_registry("shapely", "minimal") do
        assert_match(/\ATraffic — @shapely /, okf("graph", "@", "--traffic").out)

        data = json(okf("graph", "@shapely", "--traffic", "--json", "--cut", "1"))
        assert_equal "shapely", data.fetch("slug")
        assert_equal fixture("shapely"), data.fetch("bundle")
        assert_equal 1, data.fetch("cut")
        assert_equal %w[flows core], [ data.fetch("arcs").first["source"], data.fetch("arcs").first["target"] ]
      end
    end

    test "a ref and its path report the same traffic, differing only in the identity named" do
      with_registry("shapely") do
        by_ref = json(okf("graph", "@shapely", "--traffic", "--json", "--cut", "1"))
        by_path = json(okf("graph", fixture("shapely"), "--traffic", "--json", "--cut", "1"))

        assert_equal by_ref.reject { |key, _| %w[bundle slug].include?(key) },
          by_path.reject { |key, _| %w[bundle slug].include?(key) }
        refute by_path.key?("slug"), "a path names no slug"
      end
    end

    test "an unknown slug is refused before --traffic is honoured" do
      with_registry("shapely") do
        result = okf("graph", "@nope", "--traffic")

        assert_equal 2, result.status
        assert_empty result.out
      end
    end

    test "a malformed ref-named bundle is best-effort — skips noted, exit 0" do
      with_registry("malformed") do
        result = okf("graph", "@malformed")

        assert_equal 0, result.status
        assert_match(/\AGraph — @malformed .* \(3 concepts, 0 links\)\n\z/, result.out)
        assert_match(/note: skipped 2 unusable file\(s\)/, result.err)
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
      okf("registry", "set", dir, "--as", "doomed")
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
