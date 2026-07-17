# frozen_string_literal: true

require_relative "../cli_integration_case"

module AcrossBundles
  # `okf render` bakes one bundle into one HTML page. A second is a usage error —
  # and since render's whole output is a document (to stdout, or to -o's file),
  # the refusal must leave both empty: no page, no file.
  class CLIRenderTest < CLIIntegrationCase
    test "two directories: exit 2, the message names the second, stdout stays empty" do
      result = okf("render", fixture("conformant"), fixture("minimal"))

      assert_equal 2, result.status
      assert_equal "error: unexpected argument '#{fixture("minimal")}'\n", result.err
      assert_empty result.out # not one line of `conformant`'s page
    end

    test "two @refs are refused the same way" do
      with_registry("conformant", "minimal") do
        result = okf("render", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_equal "error: unexpected argument '@minimal'\n", result.err
        assert_empty result.out
      end
    end

    test "a dir mixed with a @ref is refused in either order" do
      with_registry("conformant", "minimal") do
        dir_first = okf("render", fixture("conformant"), "@minimal")
        ref_first = okf("render", "@conformant", fixture("minimal"))

        assert_equal 2, dir_first.status
        assert_equal 2, ref_first.status
        assert_match(/unexpected argument '@minimal'/, dir_first.err)
        assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, ref_first.err)
        assert_empty dir_first.out + ref_first.out
      end
    end

    test "three bundles: the message names the first unexpected argument" do
      result = okf("render", fixture("conformant"), fixture("minimal"), fixture("empty"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      refute_match(/empty/, result.err)
    end

    test "the refusal is a usage verdict (2) — render itself never fails a bundle (1)" do
      out = File.join(@out_dir, "structural.html")
      assert_equal 0, okf("render", fixture("structural"), "-o", out).status # advisory even on a §9 reject

      second = okf("render", fixture("structural"), fixture("minimal"), "-o", out)

      assert_equal 2, second.status
      refute_equal 1, second.status
      assert_empty second.out
    end

    test "the extras check outranks the directory check" do
      result = okf("render", File.join(BUNDLES, "does-not-exist"), fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument/, result.err)
      refute_match(/is not a directory/, result.err)
    end

    test "-o's value is never mistaken for a second bundle" do
      out = File.join(@out_dir, "graph.html")
      result = okf("render", fixture("conformant"), "-o", out)

      assert_equal 0, result.status
      assert_match(/wrote 3 concepts to #{Regexp.escape(out)}/, result.out)
      assert_match(/<title>OKF · /, read_utf8(out))
    end

    test "-t, -l and --layout values are values too, even one shaped like a bundle" do
      out = File.join(@out_dir, "titled.html")
      result = okf("render", fixture("minimal"), "-t", fixture("conformant"), "-l", "https://example.com/src", "--layout", "grid", "-o", out)

      assert_equal 0, result.status
      assert_match(/wrote 1 concept/, result.out)
      # `-t <a real bundle dir>` titled the page; it did not render that bundle.
      assert_match(/<title>OKF · #{Regexp.escape(fixture("conformant"))}</, read_utf8(out))
    end

    test "a second bundle behind -o and its value is refused, and the file is never written" do
      out = File.join(@out_dir, "never.html")
      result = okf("render", fixture("conformant"), "-o", out, fixture("minimal"))

      assert_equal 2, result.status
      assert_match(/unexpected argument '#{Regexp.escape(fixture("minimal"))}'/, result.err)
      assert_empty result.out
      refute File.exist?(out), "refused invocation must not write #{out}"
    end

    test "a bad -o path is a usage error about the flag, not about a bundle" do
      result = okf("render", fixture("minimal"), "-o", fixture("conformant"))

      assert_equal 2, result.status
      assert_match(/cannot write #{Regexp.escape(fixture("conformant"))}/, result.err)
      refute_match(/unexpected argument/, result.err) # the value was never taken for a bundle
    end
  end
end
