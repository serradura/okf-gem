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

    test "--json emits a machine-readable report" do
      result = okf("validate", fixture("malformed"), "--json")
      report = JSON.parse(result.out)

      assert_equal false, report["conformant"]
      assert_equal 5, report["counts"]["concepts"]
      assert_equal 4, report["errors"].size
      assert(report["errors"].all? { |e| e.key?("path") && e.key?("message") })
    end
  end
end
