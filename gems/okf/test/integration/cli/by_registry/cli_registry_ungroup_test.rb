# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry ungroup <slug> <@member…>` end-to-end — remove members from a
# group. Removing the last member deletes the group (an empty group resolves to
# nothing). Writes the registry (exit 0 on success, 2 on a usage error).
class CLIRegistryUngroupTest < CLIIntegrationCase
  test "removing a member leaves the group with the rest" do
    with_registry("conformant", "minimal") do
      okf("registry", "group", "docs", "@conformant", "@minimal")

      result = okf("registry", "ungroup", "docs", "@conformant")

      assert_equal 0, result.status
      assert_match(/ungrouped @conformant from docs/, result.out)
      assert_equal %w[minimal], json(okf("registry", "list", "--json"))["groups"].first["members"]
    end
  end

  test "removing the last member deletes the group" do
    with_registry("conformant") do
      okf("registry", "group", "docs", "@conformant")

      result = okf("registry", "ungroup", "docs", "@conformant")

      assert_equal 0, result.status
      assert_match(/removed empty group docs/, result.out)
      assert_equal [], json(okf("registry", "list", "--json"))["groups"], "the emptied group is gone"
    end
  end

  test "an unknown group is a usage error (exit 2)" do
    with_registry("conformant") do
      result = okf("registry", "ungroup", "ghost", "@conformant")

      assert_equal 2, result.status
      assert_match(/no such group: ghost/, result.err)
    end
  end

  test "removing a non-member changes nothing (exit 0)" do
    with_registry("conformant", "minimal") do
      okf("registry", "group", "docs", "@conformant")

      result = okf("registry", "ungroup", "docs", "@minimal")

      assert_equal 0, result.status
      assert_equal %w[conformant], json(okf("registry", "list", "--json"))["groups"].first["members"]
    end
  end

  test "ungroup with no member named is a usage error (exit 2)" do
    with_registry("conformant") do
      okf("registry", "group", "docs", "@conformant")

      assert_equal 2, okf("registry", "ungroup", "docs").status
    end
  end
end
