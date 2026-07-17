# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf files` lists one bundle's files by folder. A second bundle is a usage
  # error — two file trees under one heading would say nothing true about either.
  class CLIFilesTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("files", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no tree for `conformant` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("files", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("files", fixture("conformant"), "@minimal")
        ref_first = okf("files", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("files", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — files itself never fails a bundle (1)" do
      assert_equal 0, okf("files", fixture("structural")).status # advisory even on a §9 reject

      second = okf("files", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("files", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "--area's value is never mistaken for a second bundle" do
      result = okf("files", fixture("conformant"), "--area", "tables")

      assert_equal 0, result.status
      assert_match(/2 of 3 files/, result.out)
      assert_match(/customers\.md/, result.out)
    end

    test "--type and --tag values are values too" do
      assert_match(/2 of 3 files/, okf("files", fixture("conformant"), "--type", "BigQuery Table").out)
      assert_match(/1 of 3 files/, okf("files", fixture("conformant"), "--tag", "orders").out)
    end

    test "a filter value that names a real directory on disk is still a value" do
      result = okf("files", fixture("conformant"), "--tag", fixture("minimal"))

      assert_equal 0, result.status # the path matches no tag; it is not a second bundle
      assert_match(/0 of 3 files/, result.out)
    end

    test "a filter plus a projection still pairs with one bundle" do
      payload = json(okf("files", fixture("conformant"), "--area", "tables", "--except", "description"))

      assert_equal 2, payload["count"]
      refute_includes payload["files"].first.keys, "description"
    end

    test "a second bundle behind a flag and its value is still refused" do
      result = okf("files", fixture("conformant"), "--area", "tables", fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      assert_empty result.out
    end
  end
end
