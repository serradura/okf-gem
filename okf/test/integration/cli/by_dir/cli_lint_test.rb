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

      assert_match(%r{uncited\.md: body has external link\(s\) but no sources}, result.out)
      assert_match(%r{badcite\.md: source target `/nope\.md` does not exist}, result.out)
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
    # ── the v0.2 checks (WI-3) ───────────────────────────────────────────────

    test "the uncurated v0.2 bundle renders the Attestation and Migration categories, exit 0" do
      result = okf("lint", fixture("v0_2-uncurated"))

      assert_equal 0, result.status
      assert_match(/Attestation/, result.out)
      assert_match(/Migration/, result.out)
      assert_match(/Provenance/, result.out)
      assert_match(/incomplete-computation\.md: Attested Computation with no computation/, result.out)
      assert_match(/both-computation\.md: Attested Computation provides its computation twice/, result.out)
      assert_match(/unattributed\.md: footnote `\[\^missing-source\]` has no matching sources\[\]\.id/, result.out)
      assert_match(/unused-source\.md: source `uncited-source` is never cited/, result.out)
      assert_match(/unprefixed\.md: verified\.by `owner` matches none of §7's forms/, result.out)
    end

    test "the conformant v0_2 baseline lints clean, and gates clean" do
      # The fixture the malformed and uncurated bundles are read against. Every
      # v0.2 family is populated here, so a new check that misreads one of them
      # shows up as a warning on the bundle that has nothing wrong with it —
      # which is exactly how `broken_attestation_ref` shipped a false positive
      # on its first cut, against a `references/` path §6.2 reads as relative.
      result = okf("lint", fixture("v0_2"))

      assert_match(/✓ healthy — no issues/, result.out)
      assert_equal 0, okf("lint", fixture("v0_2"), "--fail-on", "warn").status
      assert_equal 0, okf("lint", fixture("v0_2"), "--fail-on", "info").status
    end

    test "every check id belongs to exactly one display category" do
      # A finding whose check sits in no category is counted in the summary and
      # printed nowhere: the `--json` report carries it and the human report
      # silently drops it. That is how a new check ships invisible.
      require "okf/cli"
      categorized = OKF::CLI::Lint::LINT_CATEGORIES.values.flatten

      assert_equal OKF::Bundle::Linter::CHECKS.sort, categorized.sort,
        "a check outside the category map prints nowhere; one in two categories prints twice"
    end

    test "a §10 resource naming a file the bundle does not carry is a warn" do
      # `incomplete_computation` asks whether a contract names its computation;
      # nothing asked whether what it names is *there*. A dangling executor,
      # attester or computation path is a contract no consumer can follow —
      # the same defect `broken_source` already reports for sources[].
      result = okf("lint", fixture("v0_2-uncurated"))

      assert_match(%r{dangling-executor\.md: executor\.resource `/references/skills/missing-runbook\.md` }, result.out)
      assert_equal 1, okf("lint", fixture("v0_2-uncurated"), "--only", "broken_attestation_ref",
        "--fail-on", "warn").status, "a contract pointing at nothing is gateable"
    end

    test "expired fires on the stale_after day itself and not the day before (--today)" do
      on_the_day = okf("lint", fixture("v0_2-uncurated"), "--today", "2000-01-01", "--only", "expired")
      day_before = okf("lint", fixture("v0_2-uncurated"), "--today", "1999-12-31", "--only", "expired")

      assert_match(/expired\.md: expired on 2000-01-01 \(stale_after\)/, on_the_day.out)
      refute_match(/expired on/, day_before.out)
      assert_equal 0, on_the_day.status, "expired is info; it reports, it does not gate"
    end

    test "the CLI supplies a clock by default, so expired reports without --today" do
      # The fixture's stale_after is 2000-01-01 — far past on any wall clock, so
      # this asserts the default-clock path without depending on today's date.
      result = okf("lint", fixture("v0_2-uncurated"))

      assert_match(/expired\.md: expired on 2000-01-01/, result.out)
    end

    test "an unparseable stale_after yields the validate warning and never an expired finding" do
      result = okf("lint", fixture("v0_2-malformed"), "--today", "2099-01-01", "--json")

      assert_empty json(result)["findings"].select { |f| f["check"] == "expired" },
        "malformed must never read as expired"
    end

    test "the twins' v0.1 half emits exactly the two Migration findings, as info" do
      report = json(okf("lint", fixture("twins/v0_1"), "--json"))

      checks = report["findings"].map { |f| f["check"] }.sort
      assert_equal %w[legacy_citations legacy_timestamp], checks
      assert(report["findings"].all? { |f| f["severity"] == "info" })
      timestamps = report["findings"].find { |f| f["check"] == "legacy_timestamp" }
      assert_nil timestamps["path"], "one finding per bundle; the members live in the metric"
      assert_equal [ "tables/customers.md", "tables/orders.md" ], timestamps["metric"]["concepts"]
    end

    test "a fully migrated bundle emits zero Migration findings" do
      report = json(okf("lint", fixture("twins/v0_2"), "--json"))

      assert_empty report["findings"].select { |f| f["check"].start_with?("legacy_") }
    end

    test "--fail-on info gates what --fail-on warn deliberately does not" do
      # twins/v0_1's only findings are expired-free info (the two Migration
      # rows), so warn stays green and info goes red — gateability without a
      # severity promotion.
      assert_equal 0, okf("lint", fixture("twins/v0_1"), "--fail-on", "warn").status
      assert_equal 1, okf("lint", fixture("twins/v0_1"), "--fail-on", "info").status
      assert_equal 0, okf("lint", fixture("twins/v0_1")).status
    end

    test "a migration campaign is --only the two legacy checks with --fail-on info" do
      campaign = %w[--only legacy_timestamp,legacy_citations --fail-on info]

      assert_equal 1, okf("lint", fixture("twins/v0_1"), *campaign).status
      assert_equal 0, okf("lint", fixture("twins/v0_2"), *campaign).status
    end

    test "lint confesses the checks it could not run, in both formats" do
      report = json(okf("lint", fixture("conformant"), "--json"))
      assert_equal [ "stale" ], report["stats"]["skipped_checks"],
        "the CLI supplies a clock, so only the cutoff-gated check skips"

      human = okf("lint", fixture("conformant"))
      assert_match(/skipped: stale/, human.out)

      with_cutoff = json(okf("lint", fixture("conformant"), "--stale-after", "90d", "--json"))
      assert_empty with_cutoff["stats"]["skipped_checks"]
    end

    test "the report prints the bundle's trust and status posture" do
      result = okf("lint", fixture("v0_2"))

      assert_match(/trust: unverified \d+, machine-confirmed \d+, human-reviewed \d+/, result.out)
      assert_match(/status: /, result.out)
    end

    test "--stale-after accepts exactly the timestamps it can parse" do
      # ISO_CUTOFF admitted a space-separated timestamp that Date.iso8601 then
      # refused, so the constant documented a grammar one branch wider than the
      # real one — a value that matched the rule and failed anyway.
      assert_equal 2, okf("lint", fixture("v0_2"), "--stale-after", "2026-01-01 09:00:00").status,
        "a space-separated timestamp is refused, and refused by the grammar rather than by the parser"
      assert_equal 0, okf("lint", fixture("v0_2"), "--stale-after", "2026-01-01T09:00:00Z").status,
        "the T-separated form is the one that parses, and it still works"
    end

    test "--stale-after refuses the spellings it would silently reinterpret" do
      # `2026-W01-1` was read as 2025-12-29 here while `--today` exited 2 on the
      # identical spelling — one flag family answering two ways.
      %w[2026-W01-1 20260101].each do |spelling|
        result = okf("lint", fixture("v0_2-uncurated"), "--stale-after", spelling)

        assert_equal 2, result.status, "--stale-after #{spelling}"
        assert_match(/invalid --stale-after `#{Regexp.escape(spelling)}`/, result.err)
      end

      assert_equal 0, okf("lint", fixture("v0_2-uncurated"), "--stale-after", "2026-01-01").status,
        "the spelling it documents still works"
      assert_equal 0, okf("lint", fixture("v0_2-uncurated"), "--stale-after", "90d").status,
        "and so does the relative form"
    end

    test "--stale-after still takes a full timestamp, which is what generated.at looks like" do
      # A cutoff is a moment, unlike --today's calendar day, and the value a
      # reader has to hand is a concept's own `generated.at`. Narrowing this to
      # a bare date refused exactly the form they would paste.
      moment = okf("lint", fixture("v0_2-uncurated"), "--stale-after", "2026-06-03T00:00:00Z", "--only", "stale", "--json")
      day = okf("lint", fixture("v0_2-uncurated"), "--stale-after", "2026-06-03", "--only", "stale", "--json")

      assert_equal 0, moment.status, moment.err
      assert_equal json(day)["findings"], json(moment)["findings"],
        "the time of day is reduced away, the way it always was"
    end

    test "--today takes YYYY-MM-DD and refuses the other ISO 8601 spellings it once accepted" do
      # The flag documents DATE and its refusal says "use YYYY-MM-DD", while
      # Date.iso8601 also parses the basic and week forms. The other end of the
      # comparison — Concept#stale_after_date — is strict, so accepting them
      # left the two halves of one comparison on different grammars.
      %w[20000101 2000-W01-1].each do |spelling|
        result = okf("lint", fixture("v0_2-uncurated"), "--today", spelling)

        assert_equal 2, result.status, "--today #{spelling}: a usage error, not a silent reinterpretation"
        assert_match(/invalid --today `#{Regexp.escape(spelling)}`/, result.err)
      end
    end

    test "--today rejects a value that is not a date (exit 2)" do
      result = okf("lint", fixture("conformant"), "--today", "soon")

      assert_equal 2, result.status
      assert_match(/invalid --today `soon`/, result.err)
    end

    test "a relative link that escapes the bundle root is reported verbatim, never resolved" do
      # §5.1 resolution stops at the root: `../../escaped.md` names nothing the
      # bundle can reach, so the finding carries the spelling as written — a
      # resolved absolute path would leak the machine's layout into the report.
      result = okf("lint", fixture("references-trap"), "--json", "--only", "missing_concept")
      finding = json(result).fetch("findings").first

      assert_equal 0, result.status
      assert_equal "missing_concept", finding.fetch("check")
      assert_equal "../../escaped.md", finding.fetch("path")
      assert_equal [ "metrics/report" ], finding.fetch("metric").fetch("sources")
    end
  end
end
