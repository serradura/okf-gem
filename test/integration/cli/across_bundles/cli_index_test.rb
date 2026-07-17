# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf index` maps one bundle's directories. A second bundle is a usage error —
  # and `--area`'s value, which is repeatable and directory-shaped, must never be
  # read as one.
  class CLIIndexTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("index", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no map for `conformant` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("index", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("index", fixture("conformant"), "@minimal")
        ref_first = okf("index", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("index", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — index itself never fails a bundle (1)" do
      assert_equal 0, okf("index", fixture("structural")).status # advisory even on a §9 reject

      second = okf("index", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("index", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "--area's value is never mistaken for a second bundle" do
      result = okf("index", fixture("conformant"), "--area", "tables")

      assert_equal 0, result.status
      assert_match(/1 directory/, result.out)
      assert_match(%r{tables/}, result.out)
    end

    test "--area is repeatable, and every repeat is a value, not a bundle" do
      result = okf("index", fixture("conformant"), "--area", "root", "--area", "tables")

      assert_equal 0, result.status
      assert_match(/2 directories/, result.out)
    end

    test "an --area value that names a real directory on disk is still a value" do
      result = okf("index", fixture("conformant"), "--area", fixture("minimal"))

      assert_equal 0, result.status # the path filters nothing; it is not a second bundle
      assert_match(/0 directories/, result.out)
    end

    test "--fields and --no-body still pair with one bundle" do
      assert_equal 0, okf("index", fixture("conformant"), "--no-body").status

      payload = json(okf("index", fixture("conformant"), "--fields", "dir,count"))
      assert_equal %w[dir count], payload["directories"].first.keys
    end

    test "a second bundle behind a flag and its value is still refused" do
      result = okf("index", fixture("conformant"), "--area", "tables", fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      assert_empty result.out
    end
  end
end
