# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # The verb the boundary was found on: `okf lint <a> <b>` once linted `a`,
  # dropped `b`, and exited 0 — a confident report about a bundle the user never
  # named. It exits 2 now, and this file is the guard on that fix.
  class CLILintTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("lint", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # the old bug printed `conformant`'s report right here
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("lint", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("lint", fixture("conformant"), "@minimal")
        ref_first = okf("lint", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("lint", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2), never --fail-on warn's failing one (1)" do
      assert_equal 1, okf("lint", fixture("unhealthy"), "--fail-on", "warn").status # the bundle itself gates

      second = okf("lint", fixture("unhealthy"), fixture("minimal"), "--fail-on", "warn")

      assert_equal 2, second.status
      refute_equal 1, second.status # 1 would claim `unhealthy` was linted; it was not
      assert_empty second.out
    end

    test "the second bundle is refused before either is read" do
      result = okf("lint", fixture("malformed"), fixture("minimal"))

      assert_equal 2, result.status
      # `lint malformed` alone notes its unparseable files on stderr; that note's
      # absence proves the reader never ran.
      refute_match(/skipped 2 file/, result.err)
    end

    test "--min-body's value is never mistaken for a second bundle" do
      result = okf("lint", fixture("conformant"), "--min-body", "100")

      assert_equal 0, result.status
      assert_match(/concepts: 3/, result.out)
    end

    test "every value-taking flag still pairs with one bundle" do
      assert_equal 0, okf("lint", fixture("stale"), "--stale-after", "2015-01-01").status
      assert_equal 0, okf("lint", fixture("unhealthy"), "--only", "orphan").status
      assert_equal 0, okf("lint", fixture("unhealthy"), "--except", "orphan").status
      assert_equal 0, okf("lint", fixture("conformant"), "--fail-on", "never").status
      assert_equal 0, okf("lint", "--min-body", "100", fixture("conformant")).status # flags may lead
    end

    test "a second bundle behind a flag and its value is still refused" do
      result = okf("lint", fixture("conformant"), "--min-body", "100", fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      assert_empty result.out
    end
  end
end
