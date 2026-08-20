# frozen_string_literal: true

require_relative "../cli_integration_case"

# The twins: the same knowledge written once in each spec version's spelling, run
# through the whole pipeline and asserted *equal*.
#
# This is the one integration file not named for a command, because the property
# it pins is not a command's. Unit tests prove each accessor answers correctly
# for each spelling; they cannot catch the bug this change is shaped to produce,
# which lives in the derivative sites — the catalog row, ROW_FIELDS, the linter's
# check ids. A missed edit there passes every unit test and silently drops a
# field from the CLI's output.
#
# The assertion is an equality between two runs rather than a golden file: two
# golden files can both be wrong in the same way and still pass.
#
# Exclusions are named, not quiet, and each is asserted to be the *only*
# difference so it cannot silently start hiding a second one. What is left is not
# closeable by any amount of reading rule, because migrating genuinely moves text
# from one place to another:
#
#   `generated_by` and the    v0.1 has no way to express an actor, or to declare
#   `generated` boolean       a `generated` key at all
#   the Migration findings    exist precisely to say one half is the old spelling
#   the body                  a migrated concept's `# Citations` section is gone
#   a search snippet          a source-only hit snippets from the body in v0.1 and
#                             from the source text in v0.2 — a move, not a loss
module ByDir
  # Bundles named by path — the plain form every verb accepts.
  class CLITwinsTest < CLIIntegrationCase
    # Every registered verb is either compared by this file or named here with
    # the argument for its absence — and the union test below is what keeps a
    # new verb from skipping the sweep silently. `skill` writes files and takes
    # no bundle; `registry` is stateful and takes no bundle; `server` has no
    # output to diff (its mount is asserted instead, below).
    COMPARED = %i[validate lint catalog search graph files types tags stats index dirs loose references render].freeze
    SKIPPED = %i[skill registry server].freeze

    # The fixtures that may keep the retired v0.1 spellings: the twins' v0.1
    # half is the property under test, and the uncurated bundle's legacy.md is
    # the Migration checks' own fixture. Everything else speaks v0.2 — pinned
    # here so a new fixture cannot quietly reintroduce the old spelling.
    LEGACY_FIXTURES = %w[twins/v0_1 v0_2-uncurated/legacy.md].freeze

    def old_spelling
      fixture("twins/v0_1")
    end

    def new_spelling
      fixture("twins/v0_2")
    end

    test "the sweep covers every registered verb — compared plus argued skips, no residue" do
      require "okf/cli"
      all = OKF::CLI.commands.map(&:id).sort

      assert_equal all, (COMPARED + SKIPPED).sort,
        "a verb outside both lists has escaped the twins sweep"
      assert_equal %i[registry server skill], SKIPPED.sort,
        "the skip list is a literal; joining it requires an argued edit here"
    end

    test "no fixture keeps the old spelling except the ones whose purpose is the legacy path" do
      offenders = Dir.glob(File.join(BUNDLES, "**", "*.md")).select do |path|
        content = read_utf8(path)
        content.match?(/^timestamp:/) || content.include?("# Citations")
      end.map { |path| path.sub("#{BUNDLES}/", "") }

      stray = offenders.reject { |path| LEGACY_FIXTURES.any? { |keep| path.start_with?(keep) } }
      assert_empty stray, "these fixtures carry a retired spelling without being the legacy path's own"
    end

    test "both halves are conformant, and validate reports them identically" do
      old = okf("validate", old_spelling, "--json")
      new = okf("validate", new_spelling, "--json")

      assert_equal 0, old.status
      assert_equal 0, new.status
      assert_equal json(old).reject { |k, _| k == "bundle" }, json(new).reject { |k, _| k == "bundle" }
    end

    test "the catalog reads both halves identically once the unexpressable fields are projected away" do
      # `--except generated_by,generated` is the exclusion the twins can never
      # lose: §5.2 makes `by` REQUIRED within `generated`, and a v0.1
      # `timestamp` carries no actor and no `generated` key — so the spellings
      # genuinely cannot express the same thing here, and projecting the fields
      # away is honest where an actor-less v0.2 twin would be a fixture bent to
      # fit.
      old = okf("catalog", old_spelling, "--json", "--except", "generated_by,generated")
      new = okf("catalog", new_spelling, "--json", "--except", "generated_by,generated")

      assert_equal 0, old.status
      assert_equal json(old)["concepts"], json(new)["concepts"]
    end

    test "generated_by and the generated boolean are the only catalog fields the halves disagree on" do
      old = json(okf("catalog", old_spelling, "--json"))["concepts"]
      new = json(okf("catalog", new_spelling, "--json"))["concepts"]

      differing = old.zip(new).flat_map { |a, b| a.keys.reject { |key| a[key] == b[key] } }.uniq.sort
      assert_equal %w[generated generated_by], differing,
        "the retired `timestamp` column is gone entirely; what is left is what v0.1 cannot express"
    end

    test "both halves answer generated_at, and only the v0.2 one names who" do
      old = json(okf("catalog", old_spelling, "--json"))["concepts"]
      new = json(okf("catalog", new_spelling, "--json"))["concepts"]

      assert_equal %w[2026-05-20 2026-05-28], old.map { |row| row["generated_at"] }.sort,
        "lifted from the v0.1 timestamp by the §13.1 fallback"
      assert_equal old.map { |row| row["generated_at"] }, new.map { |row| row["generated_at"] }
      assert_equal [ nil, nil ], old.map { |row| row["generated_by"] }
      assert_equal %w[human:maintainer human:maintainer], new.map { |row| row["generated_by"] }
      assert_equal [ false, false ], old.map { |row| row["generated"] }
      assert_equal [ true, true ], new.map { |row| row["generated"] }
    end

    test "both halves report the same source count, from opposite spellings" do
      old = json(okf("catalog", old_spelling, "--json"))["concepts"]
      new = json(okf("catalog", new_spelling, "--json"))["concepts"]

      assert_equal [ 2, 2 ], old.map { |row| row["sources"] }, "counted from the # Citations list"
      assert_equal old.map { |row| row["sources"] }, new.map { |row| row["sources"] }
    end

    test "the graph is identical — ids, edges and types never depended on the spelling" do
      old = json(okf("graph", old_spelling, "--json"))
      new = json(okf("graph", new_spelling, "--json"))

      # Bodies are excluded because they genuinely differ: migrating moves the
      # `# Citations` list out of the body and into frontmatter. Everything the
      # graph is *for* — nodes, edges, types — is untouched by that: an
      # in-bundle sources[].resource is an edge (WI-1), so lifting a citation
      # into frontmatter deletes nothing.
      assert_equal old["nodes"].map { |node| node.reject { |k, _| k == "body" } },
        new["nodes"].map { |node| node.reject { |k, _| k == "body" } }
      assert_equal old["edges"], new["edges"]
      assert_equal 2, old["edges"].length
    end

    test "lint agrees on everything but the Migration findings the v0.1 half earns" do
      old = json(okf("lint", old_spelling, "--json"))["findings"].map { |f| [ f["check"], f["path"] ] }
      new = json(okf("lint", new_spelling, "--json"))["findings"].map { |f| [ f["check"], f["path"] ] }

      assert_equal [], new - old, "the v0.2 half must earn no finding the v0.1 half does not"
      assert_equal [ [ "legacy_citations", nil ], [ "legacy_timestamp", nil ] ], (old - new).sort,
        "the v0.1 half legitimately fires Migration; that is the checks working, not a divergence"
    end

    test "excluding Migration, the two halves lint identically" do
      # `missing_generated` and `uncited_external` would have differed here once:
      # they read `timestamp` and the `# Citations` section directly. They read
      # through the accessors now, so the reports match with nothing else
      # projected away — only the findings *about* being v0.1 remain.
      old = okf("lint", old_spelling, "--json", "--except", "legacy_timestamp,legacy_citations")
      new = okf("lint", new_spelling, "--json")

      assert_equal json(old)["findings"], json(new)["findings"]
      assert_equal json(old)["healthy"], json(new)["healthy"]
    end

    test "the trust and status distributions match, because neither half declares either" do
      old = json(okf("lint", old_spelling, "--json"))["stats"]
      new = json(okf("lint", new_spelling, "--json"))["stats"]

      assert_equal old["trust"], new["trust"]
      assert_equal old["status"], new["status"]
      assert_equal({ "unverified" => 2, "machine-confirmed" => 0, "human-reviewed" => 0 }, new["trust"])
      assert_equal({ "stable" => 2 }, new["status"])
    end

    # ── the read verbs that carry no §5 field at all ────────────────────────────
    #
    # Seven verbs answer about structure — files, types, tags, counts, the §8 map,
    # the directory tree, what is unreachable — and none of them has a field the
    # reading rule touches. That is precisely why they are asserted: "this verb is
    # version-invariant" is a claim, and an unasserted claim is how a field added
    # to a row later starts diverging quietly. Each is proven in both output
    # formats, because the human renderer and the JSON one are separate code and
    # only one of them was ever going to be checked.

    test "files reads both halves identically" do
      assert_twins("files")
    end

    test "types reads both halves identically" do
      assert_twins("types")
    end

    test "tags reads both halves identically" do
      assert_twins("tags")
    end

    test "stats reads both halves identically" do
      assert_twins("stats")
    end

    test "the §8 map reads both halves identically" do
      # `index` carries each directory's authored body, and the twins' index.md
      # files are byte-identical — so this also pins that migrating frontmatter
      # never reaches a reserved file.
      assert_twins("index")
    end

    test "dirs reads both halves identically" do
      assert_twins("dirs")
    end

    test "loose reads both halves identically" do
      assert_twins("loose")
    end

    test "references reads both halves identically" do
      # Neither half carries a references/ tree, and both halves' sources are
      # URLs — the v0.1 Citations included, once §13.1 lifts them — so the
      # equality here is two empty inventories. That is the property: migrating
      # a bundle must not conjure a pointer the old spelling never made.
      assert_twins("references")
    end

    test "search finds the same concepts in both halves, on body text and on source text alike" do
      # `sources` is a scored field and the two halves keep that text in
      # different places entirely — a `# Citations` section in the body against
      # a `sources:` list in frontmatter — so a query matching only there is the
      # sharpest test the twins have. Both find it, and they agree on the
      # question actually asked: which concepts, in which order.
      %w[orders runbook policy customer retention].each do |term|
        old = json(okf("search", old_spelling, term, "--json"))
        new = json(okf("search", new_spelling, term, "--json"))

        assert_equal old["count"], new["count"], "the halves disagree on how many concepts match #{term.inspect}"
        assert_equal old["matches"].map { |match| match["id"] }, new["matches"].map { |match| match["id"] },
          "the halves rank #{term.inspect} differently"
      end
    end

    test "a hit that never touched the moved text scores identically in both halves" do
      # The control for the divergence below: `orders` matches title, id, tags
      # and body, none of which migrating moves, so its score must be untouched.
      # Without this, the next test would be equally consistent with `sources`
      # having quietly stopped being scored at all.
      old = json(okf("search", old_spelling, "orders", "--json"))["matches"].first
      new = json(okf("search", new_spelling, "orders", "--json"))["matches"].first

      assert_equal %w[title id tags body], new["matched"]
      assert_equal old["matched"], new["matched"]
      assert_equal old["score"], new["score"]
    end

    test "migrating moves a source-only hit's snippet from body text to source text" do
      # The one search divergence migrating cannot close: in v0.1 the citation
      # text *is* body prose, so it matches `sources` and `body` both; moved to
      # frontmatter, only `sources` is left — a lower score. The snippet is a
      # *move*, not a loss: it comes from the body where the text was, and from
      # the source text where it went.
      old = json(okf("search", old_spelling, "runbook", "--json"))["matches"].first
      new = json(okf("search", new_spelling, "runbook", "--json"))["matches"].first

      assert_equal "tables/orders", old["id"]
      assert_equal old["id"], new["id"]

      assert_equal %w[sources body], old["matched"]
      assert_equal %w[sources], new["matched"], "the text is no longer in the body, because it was moved out of it"
      assert_operator new["score"], :<, old["score"]

      assert_includes old["snippet"], "runbook"
      assert_includes new["snippet"], "runbook", "the snippet moved to the source text rather than vanishing"
    end

    test "the rendered page bakes the same searchable source text from both spellings" do
      # The static page indexes source text so it ranks like `okf search` (see
      # parity_test.rb). That only holds across versions if the bake flattens
      # both spellings to the same string — asserted here where it is produced.
      old = bake(old_spelling)
      new = bake(new_spelling)

      assert_equal old["sources"], new["sources"]
      assert_equal({
        "tables/customers" => "The customer data policy https://example.com/policies/customer-data " \
                              "https://example.com/policies/retention-schedule",
        "tables/orders" => "BigQuery docs https://cloud.google.com/bigquery " \
                           "The ingestion runbook https://example.com/runbooks/ingestion"
      }, new["sources"])
    end

    test "the baked catalog and §8 map match; only the actor fields and the moved list differ" do
      old = bake(old_spelling)
      new = bake(new_spelling)

      assert_equal old["index"], new["index"]
      assert_equal old["logs"], new["logs"]
      assert_equal old["catalog"].map { |row| row.reject { |k, _| %w[generated generated_by].include?(k) } },
        new["catalog"].map { |row| row.reject { |k, _| %w[generated generated_by].include?(k) } }

      # The bodies differ, and only in the direction migrating explains: the v0.1
      # half carries a `# Citations` section that the v0.2 half has lifted into
      # frontmatter. Asserted as a subtraction so a *second* body divergence — a
      # renderer that started rewriting bodies, say — could not hide behind it.
      old["bodies"].each do |id, body|
        assert_equal body[/\A.*?(?=\n# Citations\n|\z)/m].strip, new["bodies"][id].strip
      end
    end

    test "server mounts both halves the same way" do
      # `server` is the one bundle-taking verb with no output to diff, so the
      # twins property has to be read off what it hands the runner: same mode,
      # same app class, same concept count.
      _, old_boot = okf_server(old_spelling, "--port", "0")
      _, new_boot = okf_server(new_spelling, "--port", "0")

      assert_equal booted_app(old_boot.first).class, booted_app(new_boot.first).class
      assert_equal OKF::Server::App, booted_app(new_boot.first).class
      assert_equal old_boot[2], new_boot[2]
    end

    private

    # Run one command against both halves and assert the answers are equal — in
    # JSON *and* in the human rendering, since they are separate code paths and a
    # version field reaches the row before it reaches either printer.
    #
    # The bundle's own path is the one licensed difference: the two halves live
    # in different directories, so every verb names a different bundle in its
    # header and its `bundle` key. Nothing else may differ.
    def assert_twins(verb, *rest)
      old = okf(verb, old_spelling, *rest, "--json")
      new = okf(verb, new_spelling, *rest, "--json")

      assert_equal 0, old.status, "the v0.1 half failed: #{old.err}"
      assert_equal 0, new.status, "the v0.2 half failed: #{new.err}"
      assert_equal json(old).reject { |k, _| k == "bundle" }, json(new).reject { |k, _| k == "bundle" },
        "`okf #{verb} <bundle> #{rest.join(" ")} --json` diverged between the spellings"

      old_human = okf(verb, old_spelling, *rest)
      new_human = okf(verb, new_spelling, *rest)

      assert_equal old_human.out.sub(old_spelling, "<bundle>"), new_human.out.sub(new_spelling, "<bundle>"),
        "`okf #{verb} <bundle> #{rest.join(" ")}` diverged between the spellings in its human output"
    end

    # The baked EMBED payload of a rendered page, parsed. `render` writes a whole
    # HTML document, so the twins property is read off the payload rather than
    # the file: the two pages differ in their <title> alone otherwise.
    def bake(dir)
      out = File.join(@out_dir, "#{File.basename(dir)}.html")
      result = okf("render", dir, "-o", out)
      assert_equal 0, result.status, result.err
      JSON.parse(read_utf8(out)[/const EMBED=(\{.*?\});\n/m, 1])
    end
  end
end
