# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf lint` end-to-end — the curation-quality report across the fixture bundles.
# Advisory by default (exit 0); `--fail-on warn` opts into gating.
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLILintTest < CLIIntegrationCase
    test "a file the reader cannot open is skipped, not a backtrace through the whole bundle" do
      skip_unless_permissions_bite
      dir = unreadable_bundle("locked")

      result = okf("lint", dir)

      assert_equal 0, result.status, "lint is advisory; one unusable file does not make it fail, let alone raise"
      refute_match(/\.rb:\d+/, result.err, "one bad file never breaks the rest — least of all with a stack trace")
      assert_match(/note: skipped 1 unusable file\(s\) \(run `okf validate` for details\)/, result.err)
      assert_match(/OKF lint —/, result.out, "the report still prints: the rest of the bundle is still readable")
    end

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

    test "the whole hygiene category fires on the hygiene fixture" do
      # The four hygiene checks share a fixture because they share a cause:
      # prose that reads fine and links wrong. Only this bundle triggers them —
      # no other fixture emits a single Hygiene finding.
      result = okf("lint", fixture("hygiene"))

      assert_equal 0, result.status, "curation findings never fail a bundle"
      assert_match(/Hygiene/, result.out)
      assert_match(/title "Shared Title" used by 2 concepts/, result.out)
      assert_match(/refs\.md: reference definition `\[unused\]` is defined but never used/, result.out)
      assert_match(/refs\.md: reference-style link `\[ghostref\]` has no matching definition/, result.out)
      assert_match(/selfie\.md: concept links to itself/, result.out)
    end

    test "an undefined reference is the one hygiene finding that warns" do
      # It is an *invisible* broken link: the body renders as plain text with no
      # hint anything is missing, so it is the only one worth a warn — and the
      # only reason `lint --fail-on warn` fails this bundle.
      findings = json(okf("lint", fixture("hygiene"), "--json")).fetch("findings")
      hygiene = findings.select { |f| %w[duplicate_title unused_reference_def undefined_reference self_link].include?(f["check"]) }

      assert_equal %w[duplicate_title self_link undefined_reference unused_reference_def], hygiene.map { |f| f["check"] }.sort
      warned = hygiene.select { |f| f["severity"] == "warn" }
      assert_equal [ "undefined_reference" ], warned.map { |f| f["check"] }
      assert_equal 1, okf("lint", fixture("hygiene"), "--fail-on", "warn").status
    end

    test "duplicate_title names no path, because the finding belongs to neither concept" do
      duplicate = json(okf("lint", fixture("hygiene"), "--json")).fetch("findings")
                                                                 .find { |f| f["check"] == "duplicate_title" }

      assert_nil duplicate["path"], "two files share the fault, so pointing at one of them would be a lie"
      assert_match(/used by 2 concepts/, duplicate["message"])
    end

    test "--only and --except reach the hygiene checks by name" do
      only = okf("lint", fixture("hygiene"), "--only", "self_link")
      assert_match(/links to itself/, only.out)
      refute_match(/Shared Title/, only.out)

      except = okf("lint", fixture("hygiene"), "--except", "self_link,duplicate_title")
      refute_match(/links to itself/, except.out)
      refute_match(/Shared Title/, except.out)
      assert_match(/ghostref/, except.out, "the checks not excluded still run")
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

    test "lint buckets a blank type exactly as the read views do" do
      # §9.2 makes `type: "  "` as non-conformant as a missing one, and the graph
      # was widened to say so — but lint kept its own `type || "Untyped"`, which
      # only catches nil. Two verbs then report type inventories that cannot be
      # reconciled: an agent cross-referencing them sees a bucket in one that does
      # not exist in the other.
      types = json(okf("types", fixture("malformed"), "--json"))["types"]
      stats = json(okf("lint", fixture("malformed"), "--json"))["stats"]["types"]

      assert_equal({ "Untyped" => 2, "Note" => 1 }, types.map { |row| [ row["type"], row["count"] ] }.to_h,
        "blank-type.md and no-type.md are both Untyped to the read views")
      assert_equal({ "Untyped" => 2, "Note" => 1 }, stats,
        "lint counts the same concepts, so it must reach the same inventory")
      refute_match(/^  types:    1,/, okf("lint", fixture("malformed")).out,
        "a bucket labelled with spaces renders as a blank column and reads as a typo")
    end

    test "a malformed bundle is best-effort — skips noted on stderr, exit 0" do
      result = okf("lint", fixture("malformed"))

      assert_equal 0, result.status
      assert_match(/skipped 2 unusable file/, result.err)
    end

    test "usage errors exit 2: unknown check, bad stale value, missing dir" do
      assert_equal 2, okf("lint", fixture("unhealthy"), "--only", "bogus").status
      assert_equal 2, okf("lint", fixture("conformant"), "--stale-after", "soon").status
      assert_equal 2, okf("lint", File.join(BUNDLES, "does-not-exist")).status
    end
  end
end
