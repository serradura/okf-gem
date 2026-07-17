# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf types` indexes one bundle's concept types. A second bundle is a usage
  # error — one vocabulary per bundle, and no merged view to fall back on.
  class CLITypesTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("types", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no index for `conformant` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("types", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("types", fixture("conformant"), "@minimal")
        ref_first = okf("types", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("types", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — types itself never fails a bundle (1)" do
      assert_equal 0, okf("types", fixture("structural")).status # advisory even on a §9 reject

      second = okf("types", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("types", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "--area's value is never mistaken for a second bundle" do
      result = okf("types", fixture("conformant"), "--area", "tables")

      assert_equal 0, result.status
      assert_match(/1 distinct/, result.out)
      assert_match(/BigQuery Table\s+2/, result.out)
    end

    test "--tag's value is a value too, and --json still answers about one bundle" do
      assert_match(/BigQuery Table/, okf("types", fixture("conformant"), "--tag", "sales").out)

      payload = json(okf("types", fixture("conformant"), "--tag", "orders", "--json"))
      assert_equal 1, payload["count"]
      assert_equal "BigQuery Table", payload["types"].first["type"]
    end

    test "a filter value that names a real directory on disk is still a value" do
      result = okf("types", fixture("conformant"), "--tag", fixture("minimal"))

      assert_equal 0, result.status # the path matches no tag; it is not a second bundle
      assert_match(/0 distinct/, result.out)
    end

    test "a second bundle behind a flag and its value is still refused" do
      result = okf("types", fixture("conformant"), "--area", "tables", fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      assert_empty result.out
    end
  end
end
