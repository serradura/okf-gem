# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf references` named through the registry — the §6.3 inventory re-proven
# for the @ref identity: the same tree, citers and dangling pointers reached
# via `@slug` or bare `@`, the header reading `@slug (/path)`, and the JSON
# carrying both `bundle` and `slug`.
module ByRegistry
  # Bundles named by @ref — the registry form every read verb accepts.
  class CLIReferencesTest < CLIIntegrationCase
    test "@slug inventories exactly as the path form does (exit 0)" do
      with_registry("v0_2") do
        result = okf("references", "@v0_2")

        assert_equal 0, result.status
        assert_match(/^References — @v0-2 \(#{Regexp.escape(fixture("v0_2"))}\) \(3 files\)$/, result.out)
        assert_equal okf("references", fixture("v0_2")).out.lines.drop(1), result.out.lines.drop(1),
          "naming a bundle by ref changes its header, never its content"
      end
    end

    test "--json carries both bundle (the directory) and slug (the registry name)" do
      with_registry("v0_2") do
        data = json(okf("references", "@v0_2", "--json"))

        assert_equal fixture("v0_2"), data.fetch("bundle")
        assert_equal "v0-2", data.fetch("slug")
        assert_equal 3, data.fetch("count")
        assert_equal %w[path dir kind referenced_by], data.fetch("references").first.keys
      end
    end

    test "bare @ resolves the registry default" do
      with_registry("v0_2", "conformant") do
        assert_match(/^References — @v0-2 /, okf("references", "@").out)

        okf("registry", "default", "conformant")

        assert_match(/^References — @conformant .* \(0 files\)$/, okf("references", "@").out)
      end
    end

    test "dangling pointers reach the @ref identity too" do
      with_registry("v0_2-uncurated") do
        result = okf("references", "@v0_2-uncurated")

        assert_equal 0, result.status
        assert_match(/dangling pointers:/, result.out)
        assert_match(%r{dangling-executor — executor\.resource: /references/skills/missing-runbook\.md}, result.out)
      end
    end

    test "an unknown slug fails hard (exit 2), before any inventory prints" do
      result = okf("references", "@nope")

      assert_equal 2, result.status
      assert_empty result.out
    end
  end
end
