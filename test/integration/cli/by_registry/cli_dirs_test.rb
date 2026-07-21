# frozen_string_literal: true

require_relative "../cli_integration_case"

module ByRegistry
  # `okf dirs @slug` — the same view, reached through the registry. The identity
  # is where the CLI decides what to answer about, so every assertion here is
  # about the ref resolving, not about the counts (by_dir owns those).
  class CLIDirsTest < CLIIntegrationCase
    test "@slug names a registered bundle and the header says so" do
      with_registry("conformant") do
        result = okf("dirs", "@conformant")

        assert_equal 0, result.status
        assert_match(/^Dirs — @conformant \(#{Regexp.escape(fixture("conformant"))}\)$/, result.out)
        assert_match(/^  3 dirs · 3 concepts$/, result.out)
      end
    end

    test "bare @ is the registry default" do
      with_registry("conformant", "minimal") do
        default = okf("dirs", "@")
        named = okf("dirs", "@conformant")

        assert_equal 0, default.status
        assert_equal named.out, default.out # the first registered bundle is the default
      end
    end

    test "--json carries the slug beside the directory" do
      with_registry("rooted") do
        data = json(okf("dirs", "@rooted", "--json"))

        assert_equal "rooted", data.fetch("slug")
        assert_equal fixture("rooted"), data.fetch("bundle")
        assert_equal [ ".", "services" ], data.fetch("dirs").map { |row| row["dir"] }
      end
    end

    test "an unknown slug is a usage error naming the registry file" do
      with_registry("conformant") do
        result = okf("dirs", "@nope")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @nope/, result.err)
        assert_empty result.out
      end
    end

    test "a registered directory that has since vanished fails hard, never silently" do
      dir = scratch_bundle("gone")
      okf("registry", "set", dir)
      FileUtils.rm_rf(dir)

      result = okf("dirs", "@gone")

      assert_equal 2, result.status
      assert_match(/points to #{Regexp.escape(dir)}, which is not a directory/, result.err)
    end

    test "@all is refused — dirs describes one bundle" do
      with_registry("conformant", "minimal") do
        result = okf("dirs", "@all")

        assert_equal 2, result.status
        assert_match(/@all is only supported by `okf search`/, result.err)
        assert_empty result.out
      end
    end
  end
end
