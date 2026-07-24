# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf loose` lists one bundle's degree-0 files. A second bundle is a usage
  # error — "which files float?" has no answer that spans two graphs.
  class CLILooseTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("loose", fixture("unhealthy"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no listing for `unhealthy` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("loose", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("loose", fixture("conformant"), "@minimal")
        ref_first = okf("loose", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("loose", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — loose itself never fails a bundle (1)" do
      assert_equal 0, okf("loose", fixture("structural")).status # advisory even on a §9 reject

      second = okf("loose", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("loose", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "one bundle plus a flag still answers — loose's flags take no value" do
      report = json(okf("loose", fixture("unhealthy"), "--json"))

      assert_operator report["count"], :>, 0
      assert_equal 0, okf("loose", fixture("unhealthy"), "--pretty").status
    end

    test "a second bundle behind --json is still refused, and no JSON is emitted" do
      result = okf("loose", fixture("unhealthy"), "--json", fixture("minimal"))

      assert_equal 2, result.status
      assert_empty result.out
    end
  end
end
