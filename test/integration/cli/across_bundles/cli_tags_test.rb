# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf tags` indexes one bundle's vocabulary. A second is a usage error — and
  # `--by`'s value, a bare word right where a bundle would sit, must never be
  # read as one.
  class CLITagsTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("tags", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no index for `conformant` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("tags", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("tags", fixture("conformant"), "@minimal")
        ref_first = okf("tags", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("tags", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — tags itself never fails a bundle (1)" do
      assert_equal 0, okf("tags", fixture("structural")).status # advisory even on a §9 reject

      second = okf("tags", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("tags", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "--by's value is never mistaken for a second bundle" do
      result = okf("tags", fixture("conformant"), "--by", "area")

      assert_equal 0, result.status
      assert_match(/2 distinct, by area/, result.out)
      assert_match(%r{tables/ \(2 tags\)}, result.out)
    end

    test "--type and --area values are values too, and combine with --by" do
      assert_match(/sales     2/, okf("tags", fixture("conformant"), "--type", "BigQuery Table").out)
      assert_match(/2 distinct, by type/, okf("tags", fixture("conformant"), "--by", "type", "--area", "tables").out)
    end

    test "a rejected --by value is a usage error about the flag, not about a bundle" do
      result = okf("tags", fixture("conformant"), "--by", "bogus")

      assert_equal 2, result.status
      assert_match(/invalid argument: --by bogus/, result.err)
      refute_match(/unexpected argument/, result.err) # the value was never taken for a bundle
    end

    test "a second bundle behind --by and its value is still refused" do
      result = okf("tags", fixture("conformant"), "--by", "area", fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      assert_empty result.out
    end
  end
end
