# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf validate` named through the registry — the §9 verdict is the bundle's, but
# the identity in the report is the caller's: `@slug (/path)` in the header, and
# `bundle` + `slug` side by side in the JSON.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLIValidateTest < CLIIntegrationCase
    test "@slug validates the registered bundle and names both identities" do
      with_registry("conformant") do
        result = okf("validate", "@conformant")

        assert_equal 0, result.status
        assert_match(/\AOKF v0\.1 conformance — @conformant \(#{Regexp.escape(fixture("conformant"))}\)$/, result.out,
          "the header speaks the name that was typed, and the path it resolved to")
        assert_match(/concepts: 3\s+index\.md: 2\s+log\.md: 1/, result.out)
        assert_match(/✓ conformant — no issues/, result.out)
      end
    end

    test "bare @ resolves the registry default and reports under its slug" do
      with_registry("conformant", "minimal") do
        default = okf("validate", "@")

        assert_equal 0, default.status
        assert_match(/@conformant \(#{Regexp.escape(fixture("conformant"))}\)/, default.out,
          "the first bundle registered is the default, and bare @ answers as it")
        assert_equal okf("validate", "@conformant").out, default.out, "@ and @conformant are the same read"
      end
    end

    test "--json carries the directory and the slug as separate keys" do
      with_registry("conformant") do
        report = json(okf("validate", "@conformant", "--json"))

        assert_equal fixture("conformant"), report["bundle"], "`bundle` is always the directory"
        assert_equal "conformant", report["slug"], "`slug` is always the registry name — never the same key meaning two things"
        assert_equal true, report["conformant"]
        assert_equal 3, report["counts"]["concepts"]
      end
    end

    test "a bundle named by path carries no slug — no registration is implied" do
      with_registry("conformant") do
        report = json(okf("validate", fixture("conformant"), "--json"))

        assert_equal fixture("conformant"), report["bundle"]
        refute report.key?("slug"), "the same bundle by path stays a path, though the registry knows it"
        assert_match(/\AOKF v0\.1 conformance — #{Regexp.escape(fixture("conformant"))}$/, okf("validate", fixture("conformant")).out)
      end
    end

    test "--pretty implies --json and indents the same report" do
      with_registry("conformant") do
        pretty = okf("validate", "@conformant", "--pretty")
        compact = okf("validate", "@conformant", "--json")

        assert_equal 0, pretty.status
        assert_equal JSON.parse(compact.out), JSON.parse(pretty.out)
        assert_match(/^  "slug": "conformant",$/, pretty.out)
      end
    end

    test "a non-conformant bundle named by ref still exits 1" do
      with_registry("malformed") do
        result = okf("validate", "@malformed")

        assert_equal 1, result.status, "the ref changes the name, never the verdict"
        assert_match(/\AOKF v0\.1 conformance — @malformed \(#{Regexp.escape(fixture("malformed"))}\)$/, result.out)
        assert_match(/✗ non-conformant \(4 error\(s\)\)/, result.out)
        assert_equal false, json(okf("validate", "@malformed", "--json"))["conformant"]
      end
    end

    test "an unknown slug is a usage error naming the registry file it read" do
      with_registry("conformant") do
        result = okf("validate", "@ghost")

        assert_equal 2, result.status
        assert_match(/\Aerror: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_empty result.out, "a usage error leaves stdout clean"
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move" do
      doomed = register_doomed

      with_registry("conformant") do
        result = okf("validate", "@doomed")

        assert_equal 2, result.status
        assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
          result.err)
        assert_empty result.out
      end
    end

    test "bare @ on an empty registry hints at registering one" do
      with_registry do
        result = okf("validate", "@")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @ in .*registry\.json \(okf registry set <dir>\)/, result.err,
          "nothing registered yet, so the hint is `set`, not `list`")
      end
    end

    test "--home is not validate's to offer — refs read $OKF_HOME" do
      with_registry("conformant") do
        result = okf("validate", "@conformant", "--home", @home)

        assert_equal 2, result.status
        assert_match(/invalid option: --home/, result.err)
      end
    end

    test "a second bundle is a question validate cannot answer (exit 2)" do
      with_registry("conformant", "minimal") do
        result = okf("validate", "@conformant", "@minimal")

        assert_equal 2, result.status
        assert_match(/error: unexpected argument '@minimal'/, result.err)
        assert_empty result.out, "nothing is validated when the ask is ambiguous"
      end
    end

    private

    # A registered bundle whose directory is then deleted — the stale entry every
    # ref-taking verb must refuse rather than half-answer. Returns its path.
    def register_doomed
      dir = File.join(@out_dir, "doomed")
      FileUtils.cp_r(fixture("minimal"), dir)
      okf("registry", "set", dir, "--as", "doomed", "--home", @home)
      FileUtils.rm_rf(dir)
      dir
    end
  end
end
