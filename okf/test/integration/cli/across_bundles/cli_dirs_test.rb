# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf dirs` describes one bundle. A second is a usage error: two bundles have
  # two root dirs, and merging them under one `.` is the plausible-looking wrong
  # answer the second-bundle rule exists to stop.
  class CLIDirsTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("dirs", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("dirs", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("dirs", fixture("conformant"), "@minimal")
        ref_first = okf("dirs", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "a second bundle behind --json is still refused, and no JSON is emitted" do
      result = okf("dirs", fixture("conformant"), "--json", fixture("minimal"))

      assert_equal 2, result.status
      assert_empty result.out
    end

    test "one bundle still answers, and answers about that one only" do
      assert_equal 3, json(okf("dirs", fixture("conformant"), "--json")).fetch("total")
      assert_equal 1, json(okf("dirs", fixture("minimal"), "--json")).fetch("total")
    end
  end
end
