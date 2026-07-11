# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf lint` end-to-end — the curation-quality report across the fixture bundles.
# Advisory by default (exit 0); `--fail-on warn` opts into gating.
class CLILintTest < CLIIntegrationCase
  test "an unhealthy bundle reports grouped findings but stays advisory (exit 0)" do
    result = okf("lint", fixture("unhealthy"))

    assert_equal 0, result.status
    assert_match(/Reachability/, result.out)
    assert_match(/Backlog/, result.out)
    assert_match(/orphan\.md: unreachable/, result.out)
    assert_match(/not-written\.md: referenced by 2 link/, result.out)
  end

  test "a well-curated bundle is healthy" do
    result = okf("lint", fixture("conformant"))

    assert_equal 0, result.status
    assert_match(/✓ healthy — no issues/, result.out)
    assert_match(/concepts: 3/, result.out)
  end

  test "an empty bundle is healthy with zero concepts" do
    result = okf("lint", fixture("empty"))

    assert_equal 0, result.status
    assert_match(/concepts: 0/, result.out)
    assert_match(/healthy/, result.out)
  end

  test "--fail-on warn gates on warn findings; default stays advisory" do
    assert_equal 1, okf("lint", fixture("unhealthy"), "--fail-on", "warn").status
    assert_equal 0, okf("lint", fixture("unhealthy")).status
  end

  test "--json emits stats and findings" do
    report = JSON.parse(okf("lint", fixture("unhealthy"), "--json").out)

    assert_equal false, report["healthy"]
    assert_equal 3, report["stats"]["concepts"]
    backlog = report["findings"].find { |f| f["check"] == "missing_concept" }
    assert_equal 2, backlog["metric"]["references"]
  end

  test "broken_index_entry and not_in_index fire on the navigation fixture" do
    result = okf("lint", fixture("navigation"))

    assert_match(/index links to missing concept `gone\.md`/, result.out)
    assert_match(/unlisted\.md: not listed/, result.out)
  end

  test "provenance findings fire on the provenance fixture" do
    result = okf("lint", fixture("provenance"))

    assert_match(%r{uncited\.md: body has external link}, result.out)
    assert_match(%r{badcite\.md: citation target `/nope\.md`}, result.out)
  end

  test "--min-body override changes the stub count" do
    strict = JSON.parse(okf("lint", fixture("incomplete"), "--min-body", "1000", "--json").out)
    lenient = JSON.parse(okf("lint", fixture("incomplete"), "--min-body", "1", "--json").out)

    assert_operator strict["stats"]["stubs"], :>, lenient["stats"]["stubs"]
  end

  test "--stale-after flags old concepts against an absolute cutoff" do
    flagged = okf("lint", fixture("stale"), "--stale-after", "2015-01-01")
    assert_match(/old\.md: last updated 2000-01-01/, flagged.out)
    refute_match(/fresh\.md: last updated/, flagged.out)

    refute_match(/last updated/, okf("lint", fixture("stale")).out) # disabled without the flag
  end

  test "--only and --except select which checks run" do
    only = okf("lint", fixture("unhealthy"), "--only", "orphan")
    assert_match(/orphan\.md: unreachable/, only.out)
    refute_match(/Backlog/, only.out)

    refute_match(/unreachable/, okf("lint", fixture("unhealthy"), "--except", "orphan").out)
  end

  test "a malformed bundle is best-effort — skips noted on stderr, exit 0" do
    result = okf("lint", fixture("malformed"))

    assert_equal 0, result.status
    assert_match(/skipped 2 file/, result.err)
  end

  test "usage errors exit 2: unknown check, bad stale value, missing dir" do
    assert_equal 2, okf("lint", fixture("unhealthy"), "--only", "bogus").status
    assert_equal 2, okf("lint", fixture("conformant"), "--stale-after", "soon").status
    assert_equal 2, okf("lint", File.join(BUNDLES, "does-not-exist")).status
  end
end
