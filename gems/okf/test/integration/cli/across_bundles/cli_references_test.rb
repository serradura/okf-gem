# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf references` inventories one bundle's references/ tree. A second bundle
  # is a usage error — two trees and two pointer sets merged under one heading
  # would say nothing true about either.
  class CLIReferencesTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("references", fixture("v0_2"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no inventory for `v0_2` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("v0_2", "minimal") do
        result = okf("references", "@v0_2", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("v0_2", "minimal") do
        dir_first = okf("references", fixture("v0_2"), "@minimal")
        ref_first = okf("references", "@v0_2", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "the refusal is a usage verdict (2) — references itself never fails a bundle (1)" do
      assert_equal 0, okf("references", fixture("v0_2-uncurated")).status # advisory even with dangling pointers

      second = okf("references", fixture("v0_2-uncurated"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end
  end
end
