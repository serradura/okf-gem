# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf graph` prints one bundle's nodes and edges. Two bundles are two graphs,
  # not one — only `server` mounts several — so a second is a usage error.
  class CLIGraphTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("graph", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # no counts for `conformant` before complaining
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("graph", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("graph", fixture("conformant"), "@minimal")
        ref_first = okf("graph", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("graph", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — graph itself never fails a bundle (1)" do
      assert_equal 0, okf("graph", fixture("structural")).status # advisory even on a §9 reject

      second = okf("graph", fixture("structural"), fixture("minimal"))

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the second bundle is refused before either is read" do
      result = okf("graph", fixture("malformed"), fixture("minimal"))

      assert_equal 2, result.status
      # `graph malformed` alone notes its unparseable files; the note's absence
      # proves no bundle was loaded to be half-answered about.
      refute_match(/skipped 2 file/, result.err)
    end

    test "--minimal still answers about one bundle — graph's flags take no value" do
      assert_match(/3 concepts, 6 links/, okf("graph", fixture("conformant"), "--minimal").out)
      assert_equal 0, okf("graph", fixture("conformant"), "--no-body").status

      payload = json(okf("graph", fixture("conformant"), "--minimal", "--json"))
      assert_equal 3, payload["nodes"].size
      assert_equal 2, payload["types"].size
    end

    test "a second bundle behind --minimal is still refused, whichever side it sits on" do
      trailing = okf("graph", fixture("conformant"), "--minimal", fixture("minimal"))
      leading = okf("graph", "--minimal", fixture("conformant"), fixture("minimal"))

      assert_equal 2, trailing.status
      assert_equal 2, leading.status
      assert_empty trailing.out + leading.out
    end

    test "--hubs still answers about one bundle, and a second behind it is refused" do
      assert_match(/2 of 4 concepts with inbound links/, okf("graph", fixture("shapely"), "--hubs").out)

      second = okf("graph", fixture("shapely"), "--hubs", fixture("minimal"))

      assert_equal 2, second.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, second.err)
      assert_empty second.out
    end
  end
end
