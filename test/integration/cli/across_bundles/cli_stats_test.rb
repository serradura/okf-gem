# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf stats` rolls up one bundle. A second is a usage error — summed counts
  # across two bundles are the most plausible-looking wrong answer the CLI could
  # give, so it gives none.
  class CLIStatsTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("stats", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no rollup for `conformant`, and none for the pair
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("stats", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("stats", fixture("conformant"), "@minimal")
        ref_first = okf("stats", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("stats", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — stats itself never fails a bundle (1)" do
      assert_equal 0, okf("stats", fixture("structural")).status # advisory even on a §9 reject

      second = okf("stats", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("stats", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "one bundle plus a flag still answers — stats' flags take no value" do
      payload = json(okf("stats", fixture("conformant"), "--json"))

      assert_equal 3, payload["concepts"] # the one bundle's own count, never a sum
      assert_equal 2, payload["areas"]
      assert_equal 0, okf("stats", fixture("conformant"), "--pretty").status
    end

    test "a second bundle behind --json is still refused, and no JSON is emitted" do
      result = okf("stats", fixture("conformant"), "--json", fixture("minimal"))

      assert_equal 2, result.status
      assert_empty result.out
    end
  end
end
