# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf lint` named through the registry — every knob the curation report offers,
# driven at a bundle the caller named `@slug`. The findings are the bundle's; the
# identity in the report is the caller's.
module ByRegistry
  # Bundles named by @ref — the identity form the registry gives.
  class CLILintTest < CLIIntegrationCase
    test "@slug lints the registered bundle and names both identities" do
      with_registry("unhealthy") do
        result = okf("lint", "@unhealthy")

        assert_equal 0, result.status, "lint stays advisory however the bundle was named"
        assert_match(/\AOKF lint — @unhealthy \(#{Regexp.escape(fixture("unhealthy"))}\)$/, result.out)
        assert_match(/concepts: 3\s+edges: 1/, result.out)
        assert_match(/Reachability/, result.out)
        assert_match(/orphan\.md: unreachable/, result.out)
      end
    end

    test "bare @ lints the registry default under its slug" do
      with_registry("conformant", "unhealthy") do
        default = okf("lint", "@")

        assert_equal 0, default.status
        assert_match(/\AOKF lint — @conformant \(#{Regexp.escape(fixture("conformant"))}\)$/, default.out)
        assert_match(/✓ healthy — no issues/, default.out)
        assert_equal okf("lint", "@conformant").out, default.out, "bare @ is the default bundle, spelled shorter"
      end
    end

    test "--json carries the directory and the slug beside the report" do
      with_registry("unhealthy") do
        report = json(okf("lint", "@unhealthy", "--json"))

        assert_equal fixture("unhealthy"), report["bundle"]
        assert_equal "unhealthy", report["slug"]
        assert_equal false, report["healthy"]
        assert_equal 3, report["stats"]["concepts"]
        backlog = report["findings"].find { |finding| finding["check"] == "missing_concept" }
        assert_equal 2, backlog["metric"]["references"]
      end
    end

    test "the same bundle by path carries no slug" do
      with_registry("unhealthy") do
        refute json(okf("lint", fixture("unhealthy"), "--json")).key?("slug"),
          "a path names a directory; inventing a slug would imply a registration the caller did not make"
      end
    end

    test "--pretty implies --json and indents the same report" do
      with_registry("unhealthy") do
        pretty = okf("lint", "@unhealthy", "--pretty")

        assert_equal 0, pretty.status
        assert_equal JSON.parse(okf("lint", "@unhealthy", "--json").out), JSON.parse(pretty.out)
        assert_match(/^  "slug": "unhealthy",$/, pretty.out)
      end
    end

    test "--fail-on warn gates a ref-named bundle (exit 1); the default stays advisory" do
      with_registry("unhealthy") do
        assert_equal 1, okf("lint", "@unhealthy", "--fail-on", "warn").status
        assert_equal 0, okf("lint", "@unhealthy").status
        assert_equal 1, okf("lint", "@", "--fail-on", "warn").status, "bare @ gates just the same"
      end
    end

    test "--fail-on warn on a healthy ref-named bundle exits 0" do
      with_registry("conformant") do
        assert_equal 0, okf("lint", "@conformant", "--fail-on", "warn").status, "nothing to warn about, nothing to gate"
      end
    end

    test "--min-body changes the stub count through a ref" do
      with_registry("incomplete") do
        strict = json(okf("lint", "@incomplete", "--min-body", "1000", "--json"))
        lenient = json(okf("lint", "@incomplete", "--min-body", "1", "--json"))

        assert_equal "incomplete", strict["slug"]
        assert_operator strict["stats"]["stubs"], :>, lenient["stats"]["stubs"]
      end
    end

    test "--stale-after flags old concepts through a ref" do
      with_registry("stale") do
        flagged = okf("lint", "@stale", "--stale-after", "2015-01-01")

        assert_equal 0, flagged.status
        assert_match(/old\.md: last updated 2000-01-01/, flagged.out)
        refute_match(/fresh\.md: last updated/, flagged.out)
        refute_match(/last updated/, okf("lint", "@stale").out, "the check is off without the flag")
      end
    end

    test "--only and --except select which checks run against a ref" do
      with_registry("unhealthy") do
        only = okf("lint", "@unhealthy", "--only", "orphan")
        assert_equal 0, only.status
        assert_match(/orphan\.md: unreachable/, only.out)
        refute_match(/Backlog/, only.out)

        skipped = okf("lint", "@unhealthy", "--except", "orphan")
        assert_equal 0, skipped.status
        refute_match(/unreachable/, skipped.out)
        assert_match(/Backlog/, skipped.out)
      end
    end

    test "a malformed ref-named bundle is best-effort — skips noted, exit 0" do
      with_registry("malformed") do
        result = okf("lint", "@malformed")

        assert_equal 0, result.status
        assert_match(/note: skipped 2 file\(s\) with invalid frontmatter/, result.err)
        assert_match(/OKF lint — @malformed/, result.out)
      end
    end

    test "usage errors exit 2 before the ref is even read: unknown check, bad stale value" do
      with_registry("unhealthy") do
        assert_equal 2, okf("lint", "@unhealthy", "--only", "bogus").status
        assert_match(/error: unknown check\(s\): bogus/, okf("lint", "@unhealthy", "--only", "bogus").err)

        bad_stale = okf("lint", "@unhealthy", "--stale-after", "soon")
        assert_equal 2, bad_stale.status
        assert_match(/error: invalid --stale-after `soon`/, bad_stale.err)
      end
    end

    test "an unknown slug is a usage error naming the registry file it read" do
      with_registry("unhealthy") do
        result = okf("lint", "@ghost")

        assert_equal 2, result.status
        assert_match(/\Aerror: not a registered bundle: @ghost in #{Regexp.escape(File.join(@home, "registry.json"))} \(okf registry list\)$/, result.err)
        assert_empty result.out
      end
    end

    test "a registered-but-gone directory is a usage error naming the next move" do
      doomed = register_doomed

      with_registry("unhealthy") do
        result = okf("lint", "@doomed")

        assert_equal 2, result.status
        assert_match(/\Aerror: @doomed points to #{Regexp.escape(doomed)}, which is not a directory \(okf registry del doomed, or restore it\)$/,
          result.err)
        assert_empty result.out
      end
    end

    test "bare @ on an empty registry hints at registering one" do
      with_registry do
        result = okf("lint", "@")

        assert_equal 2, result.status
        assert_match(/not a registered bundle: @ in .*registry\.json \(okf registry set <dir>\)/, result.err)
      end
    end

    test "--home is not lint's to offer — refs read $OKF_HOME" do
      with_registry("unhealthy") do
        result = okf("lint", "@unhealthy", "--home", @home)

        assert_equal 2, result.status
        assert_match(/invalid option: --home/, result.err)
      end
    end

    test "a second bundle is a question lint cannot answer (exit 2)" do
      with_registry("conformant", "unhealthy") do
        result = okf("lint", "@conformant", "@unhealthy")

        assert_equal 2, result.status
        assert_match(/error: unexpected argument '@unhealthy'/, result.err)
        assert_empty result.out
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
