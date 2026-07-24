# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf validate` answers about one bundle. A second is refused (exit 2) before
  # the first is ever read, so the conformance verdict never arrives for a
  # question nobody asked.
  class CLIValidateTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("validate", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no verdict about `conformant` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("validate", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("validate", fixture("conformant"), "@minimal")
        ref_first = okf("validate", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("validate", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err) # the third is not reported; the first stop is the answer
    end

    test "the refusal is a usage verdict (2), never the non-conformant one (1)" do
      assert_equal 1, okf("validate", fixture("structural")).status # the bundle itself fails §9

      second = okf("validate", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status # 1 would claim `structural` was judged; it was not
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("validate", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "one bundle plus a flag still answers — validate's flags take no value" do
      report = json(okf("validate", fixture("conformant"), "--json"))

      assert_equal true, report["conformant"]
      assert_equal 0, okf("validate", fixture("conformant"), "--pretty").status
    end

    test "a second bundle behind --json is still refused, and no JSON is emitted" do
      result = okf("validate", fixture("conformant"), "--json", fixture("minimal"))

      assert_equal 2, result.status
      assert_empty result.out
    end
  end
end
