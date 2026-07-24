# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry group <slug> <@member…>` end-to-end — create a named set of
# bundles, or add members to one. A group shares the slug namespace with bundles
# and resolves recursively; only `search`/`server` consume it. Writes the
# persistent registry (exit 0 on success, 2 on a usage error).
#
# $OKF_HOME is pinned at the scratch home the base class makes and removes, so the
# real ~/.okf is never touched.
class CLIRegistryGroupTest < CLIIntegrationCase
  test "grouping bundles registers a group that `registry list` shows" do
    with_registry("conformant", "minimal") do
      result = okf("registry", "group", "docs", "@conformant", "@minimal")

      assert_equal 0, result.status
      assert_match(/grouped docs → @conformant, @minimal \(2 bundles\)/, result.out)
      groups = json(okf("registry", "list", "--json"))["groups"]
      assert_equal [ { "slug" => "docs", "members" => %w[conformant minimal], "resolved" => 2 } ], groups
    end
  end

  test "members may be given bare, without the @" do
    with_registry("conformant") do
      assert_equal 0, okf("registry", "group", "docs", "conformant").status
      assert_equal %w[conformant], json(okf("registry", "list", "--json"))["groups"].first["members"]
    end
  end

  test "grouping again adds members as a union" do
    with_registry("conformant", "minimal") do
      okf("registry", "group", "docs", "@conformant")
      okf("registry", "group", "docs", "@conformant", "@minimal")

      assert_equal %w[conformant minimal], json(okf("registry", "list", "--json"))["groups"].first["members"],
        "an already-present member is not duplicated"
    end
  end

  test "a nested group resolves through to its bundle leaves" do
    with_registry("conformant", "minimal", "empty") do
      okf("registry", "group", "inner", "@minimal", "@empty")
      okf("registry", "group", "outer", "@conformant", "@inner")

      row = json(okf("registry", "list", "--json"))["groups"].find { |g| g["slug"] == "outer" }
      assert_equal 3, row["resolved"], "outer resolves conformant + inner's two leaves"
    end
  end

  test "a cycle is refused (exit 2), and nothing is written" do
    with_registry("conformant") do
      okf("registry", "group", "a", "@conformant")
      okf("registry", "group", "b", "@a")

      result = okf("registry", "group", "a", "@b")

      assert_equal 2, result.status
      assert_match(/cycle/, result.err)
      assert_equal %w[conformant], json(okf("registry", "list", "--json"))["groups"].find { |g| g["slug"] == "a" }["members"]
    end
  end

  test "a group slug colliding with a bundle is refused (exit 2)" do
    with_registry("conformant") do
      result = okf("registry", "group", "conformant", "@conformant")

      assert_equal 2, result.status
      assert_match(/slug already taken: conformant names a bundle/, result.err)
    end
  end

  test "the reserved `all` cannot name a group" do
    with_registry("conformant") do
      result = okf("registry", "group", "all", "@conformant")

      assert_equal 2, result.status
      assert_match(/reserved/, result.err)
    end
  end

  test "an unknown member is refused (exit 2)" do
    with_registry("conformant") do
      result = okf("registry", "group", "docs", "@conformant", "@ghost")

      assert_equal 2, result.status
      assert_match(/no such bundle or group: @ghost/, result.err)
    end
  end

  test "a group needs at least one member (exit 2)" do
    with_registry("conformant") do
      result = okf("registry", "group", "docs")

      assert_equal 2, result.status
    end
  end
end
