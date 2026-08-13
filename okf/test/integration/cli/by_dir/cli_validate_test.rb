# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf validate` end-to-end — the §9 conformance verdict across conformant,
# malformed (§9.1/§9.2), structural (§9.3), edge-case, and unhealthy fixtures.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLIValidateTest < CLIIntegrationCase
    test "a minimal bundle is conformant with no warnings (exit 0)" do
      status = nil
      assert_output(/✓ conformant — no issues/, "") { status = start_cli("validate", fixture("minimal")) }
      assert_equal 0, status
    end

    test "the rich conformant bundle counts reserved files and stays clean" do
      status = nil
      assert_output(/concepts: 3\s+index\.md: 2\s+log\.md: 1/, "") do
        status = start_cli("validate", fixture("conformant"))
      end
      assert_equal 0, status
    end

    test "an empty bundle is vacuously conformant (exit 0)" do
      status = nil
      assert_output(/concepts: 0.*✓ conformant/m, "") { status = start_cli("validate", fixture("empty")) }
      assert_equal 0, status
    end

    test "malformed concepts are §9.1/§9.2 errors (exit 1)" do
      result = okf("validate", fixture("malformed"))

      assert_equal 1, result.status
      assert_match(/✗ non-conformant \(4 error\(s\)\)/, result.out)
      assert_match(/no-frontmatter\.md: missing YAML frontmatter/, result.out)
      assert_match(/bad-yaml\.md: invalid YAML frontmatter/, result.out)
      assert_match(/blank-type\.md: frontmatter must include a non-empty type/, result.out)
      assert_match(/no-type\.md: frontmatter must include a non-empty type/, result.out)
    end

    test "§9.3 structural violations are errors (exit 1)" do
      result = okf("validate", fixture("structural"))

      assert_equal 1, result.status
      assert_match(/✗ non-conformant \(3 error\(s\)\)/, result.out)
      assert_match(/index\.md: root index\.md frontmatter may only include okf_version/, result.out)
      assert_match(%r{sub/index\.md: nested index\.md must not include frontmatter}, result.out)
      assert_match(/log\.md: log\.md date headings must use YYYY-MM-DD/, result.out)
    end

    test "date-only and full ISO timestamps do not warn (issue #3 regression)" do
      result = okf("validate", fixture("conformant"))

      assert_equal 0, result.status
      refute_match(/timestamp should be ISO 8601/, result.out)
    end

    test "links inside code fences are ignored, so no phantom broken-link warning" do
      result = okf("validate", fixture("edge-cases"))

      assert_equal 0, result.status
      assert_match(/✓ conformant — no issues/, result.out)
      refute_match(/fenced-only-ghost/, result.out) # the fenced link must never be seen
    end

    test "broken cross-links are tolerated warnings, not errors (§5.3)" do
      status = nil
      assert_output(%r{✓ conformant \(2 warning\(s\)\).*}m, "") do
        status = start_cli("validate", fixture("unhealthy"))
      end
      assert_equal 0, status
    end

    test "a file the reader cannot open is a §9.1 error naming it, not a backtrace" do
      skip_unless_permissions_bite
      dir = unreadable_bundle("locked")

      result = okf("validate", dir)

      assert_equal 1, result.status, "a file that cannot be read cannot be shown to carry a type — §9.1 fails, and 1 is what a failing bundle exits"
      refute_match(/\.rb:\d+/, result.err, "exit 1 means non-conformant; a backtrace means neither that nor a usage error")
      assert_match(/✗ ERROR  note\.md: .*Permission denied/, result.out,
        "the report names the file and why it could not be read, which is the whole point of failing instead of raising")
      assert_match(/✗ non-conformant \(1 error\(s\)\)/, result.out)
    end

    test "--json emits a machine-readable report" do
      result = okf("validate", fixture("malformed"), "--json")
      report = JSON.parse(result.out)

      assert_equal false, report["conformant"]
      assert_equal 5, report["counts"]["concepts"]
      assert_equal 4, report["errors"].size
      assert(report["errors"].all? { |e| e.key?("path") && e.key?("message") })
    end
    # ── the v0.2 families (§5, §10) ──────────────────────────────────────────
    #
    # Every one of these is a *warning*. §11 restates §9's three conformance
    # conditions verbatim and adds nothing to the error side, so a v0.2 shape
    # fault can never make a bundle non-conformant — which is why each test
    # below asserts exit 0 alongside the message it is about.

    test "a well-formed v0.2 bundle is conformant with no warnings at all" do
      result = okf("validate", fixture("v0_2"))

      assert_equal 0, result.status
      assert_match(/✓ conformant — no issues/, result.out)
      assert_match(/concepts: 5/, result.out)
    end

    test "an unquoted okf_version is a Psych Float and must not warn" do
      # v0_2/index.md deliberately declares `okf_version: 0.2` without quotes.
      result = okf("validate", fixture("v0_2"))

      assert_equal 0, result.status
      refute_match(/okf_version/, result.out)
    end

    test "the malformed v0.2 bundle stays conformant — every shape fault is a warning (exit 0)" do
      result = okf("validate", fixture("v0_2-malformed"))

      assert_equal 0, result.status, "a warning that became an error would break §11"
      assert_match(/✓ conformant \(\d+ warning\(s\)\)/, result.out)
      refute_match(/✗/, result.out)
    end

    test "warns on every generated shape fault (§5.2)" do
      warnings = validation_warnings("v0_2-malformed")

      assert_includes warnings["generated-not-a-mapping.md"], "generated should be a mapping"
      assert_includes warnings["generated-missing-by.md"], "generated should include by"
      assert_includes warnings["generated-bad-at.md"], "generated.at should be ISO 8601 parseable"
    end

    test "warns on verified as a whole and per entry (§5.2)" do
      warnings = validation_warnings("v0_2-malformed")

      assert_includes warnings["verified-not-a-list.md"], "verified should be a mapping or a list of mappings"
      assert_includes warnings["verified-bad-entries.md"], "verified[0] should be a mapping"
      assert_includes warnings["verified-bad-entries.md"], "verified[1] should include by"
      assert_includes warnings["verified-bad-entries.md"], "verified[2].at should be ISO 8601 parseable"
    end

    test "warns on sources and its credibility signals (§5.1)" do
      warnings = validation_warnings("v0_2-malformed")

      assert_includes warnings["sources-bad-entries.md"], "sources[0] should be a mapping"
      assert_includes warnings["sources-bad-entries.md"], "sources[1] should include resource"
      assert_includes warnings["sources-bad-entries.md"], "sources[2].last_modified should be a YYYY-MM-DD date"
      assert_includes warnings["sources-bad-entries.md"], "sources[2].usage_count should be an integer"
      assert_includes warnings["sources-bad-entries.md"], "sources[3].usage_window should be a mapping"
      assert_includes warnings["sources-not-a-list.md"], "sources should be a list"
    end

    test "warns on usage_window, status and stale_after (§5.1, §5.4, §5.5)" do
      warnings = validation_warnings("v0_2-malformed")

      assert_includes warnings["usage-window-bad.md"], "usage_window.from should be a YYYY-MM-DD date"
      assert_includes warnings["usage-window-not-a-mapping.md"], "usage_window should be a mapping"
      assert_includes warnings["status-unknown.md"], "status should be one of draft, stable, deprecated"
      assert_includes warnings["stale-after-bad.md"], "stale_after should be a YYYY-MM-DD date"
    end

    test "a date that parses is still wrong when it carries a time (§5.5)" do
      # `stale_after` is an absolute day. A value with hours in it parses
      # perfectly well and means the producer wrote something other than the
      # field the spec defines, so parsing is not the whole test.
      warnings = validation_warnings("v0_2-malformed")

      assert_includes warnings["stale-after-datetime.md"], "stale_after should be a YYYY-MM-DD date"
    end

    test "warns on the Attested Computation contract (§10.2)" do
      warnings = validation_warnings("v0_2-malformed")

      assert_includes warnings["computation-incomplete.md"], "runtime is required for an Attested Computation"
      assert_includes warnings["computation-incomplete.md"], "parameters[1] should include name"
      assert_includes warnings["computation-incomplete.md"], "parameters[2] should be a mapping"
      assert_includes warnings["computation-incomplete.md"], "executor should be a mapping"
      assert_includes warnings["computation-incomplete.md"], "attester should include resource"
      assert_includes warnings["parameters-not-a-list.md"], "parameters should be a list"
    end

    test "warns on an okf_version this gem does not know, and reads the bundle anyway (§12)" do
      result = okf("validate", fixture("v0_2-malformed"))

      assert_equal 0, result.status
      assert_match(/index\.md: okf_version `9\.9` is not a version this gem knows/, result.out)
      assert_match(/concepts: 14/, result.out, "best-effort means it still read every concept")
    end

    test "a bundle declaring a version the gem does not know still answers catalog and search" do
      assert_equal 0, okf("catalog", fixture("v0_2-malformed")).status
      assert_equal 0, okf("search", fixture("v0_2-malformed"), "generated").status
    end

    test "a v0.1 bundle earns none of the v0.2 warnings — absence is not a fault" do
      result = okf("validate", fixture("conformant"))

      assert_equal 0, result.status
      assert_match(/✓ conformant — no issues/, result.out)
    end

    test "--json carries every v0.2 warning with its path, check id and source" do
      report = json(okf("validate", fixture("v0_2-malformed"), "--json"))

      assert_equal true, report["conformant"]
      assert_empty report["errors"]
      assert_operator report["warnings"].size, :>=, 20
      assert(report["warnings"].all? { |w| w.key?("path") && w.key?("message") })
      assert(report["warnings"].all? { |w| %w[spec convention].include?(w["source"]) },
        "every warning names whether the SPEC or a gem convention states it")
      assert(report["warnings"].all? { |w| !w["check"].to_s.empty? }, "every warning carries a machine-readable check id")

      by_check = report["warnings"].group_by { |w| w["check"] }
      assert_equal "convention", by_check.fetch("source_usage_count").first["source"],
        "the usage_count integer rule is the gem's, not §5.1's"
      assert_equal "spec", by_check.fetch("sources_shape").first["source"]
    end

    private

    # Warning messages from a bundle, grouped by the file they were reported
    # against — the shape these assertions actually want, since a fixture file
    # is named for the one fault it carries.
    def validation_warnings(name)
      json(okf("validate", fixture(name), "--json"))["warnings"]
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |warning, map|
          map[warning["path"]] << warning["message"]
        end
    end
  end
end
