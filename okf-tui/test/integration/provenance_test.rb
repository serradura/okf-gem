# frozen_string_literal: true

require "test_helper"

module Integration
  # §5's families on screen, and the rule that decides whether they appear at all.
  #
  # The load-bearing constraint is okf's own: v0.2 added optional keys, so a v0.1
  # bundle must not read as deficient. Every assertion here is really about that —
  # what a bundle that declared nothing shows, and what one that declared
  # something shows beside it. `fixtures/provenance` carries both inside one
  # bundle so the difference is a property of the concept, not of the fixture.
  class ProvenanceTest < OKF::TUI::TestCase
    DOWN = OKF::TUI::App::DOWN

    # ── browse: the detail pane ─────────────────────────────────────────────

    test "a concept says when it was generated, and by whom when it says so" do
      app = app_for(dirs: "provenance", keys: "2")
      app.open_concept("ledger")

      frame = plain(frame_for(app, size: [ 120, 40 ]))
      assert_includes frame, "updated 2026-08-12T09:00:00Z by human:maintainer"
    end

    test "a v0.1 timestamp still shows, and no actor is invented for it" do
      # §13.1 lifts `timestamp:` to generated_at per key. The date survives; the
      # actor was never recorded, and printing one would be the false provenance
      # claim §5 exists to prevent.
      app = app_for(dirs: "provenance", keys: "2")
      app.open_concept("untouched")

      frame = plain(frame_for(app, size: [ 120, 40 ]))
      assert_includes frame, "updated 2026-08-12"
      refute_match(/updated 2026-08-12\S*\s+by /, frame, "an actor was invented for a lifted timestamp")
    end

    test "the trust tier is claimed only where the concept declared §5" do
      declared = app_for(dirs: "provenance", keys: "2")
      declared.open_concept("draft-note")
      # Unverified, but the concept declared `generated` — it opted into §5, so
      # its unverified is an answer rather than an absence.
      assert_includes plain(frame_for(declared, size: [ 120, 40 ])), "unverified"

      silent = app_for(dirs: "provenance", keys: "2")
      silent.open_concept("untouched")
      refute_includes plain(frame_for(silent, size: [ 120, 40 ])), "unverified",
        "a concept that declared no §5 family had a tier claimed for it"
    end

    test "a status shows only when it was declared and is not §5.4's default" do
      deprecated = app_for(dirs: "provenance", keys: "2")
      deprecated.open_concept("ledger")
      assert_includes plain(frame_for(deprecated, size: [ 120, 40 ])), "deprecated"

      # sweep.md declares `status: stable` — the same thing an absent status
      # already means, so a row saying it carries nothing the absence did not.
      default = app_for(dirs: "provenance", keys: "2")
      default.open_concept("sweep")
      frame = plain(frame_for(default, size: [ 120, 40 ]))
      refute_match(/^\s+stable\b/, frame, "a declared `stable` was printed, which is what absent already means")
      assert_includes frame, "expires 2026-12-31", "a declared stale_after should show"
    end

    test "a v0.1 bundle's detail pane carries no §5 rows it never earned" do
      app = app_for(dirs: "okf-docs", keys: "2")
      app.open_concept("overview")

      frame = plain(frame_for(app, size: [ 120, 40 ]))
      assert_includes frame, "updated ", "the lifted timestamp is still the one row a v0.1 bundle has"
      refute_includes frame, "unverified"
      refute_includes frame, "expires "
    end

    # ── health: the standing pane ───────────────────────────────────────────

    test "the conformance line names the version the bundle declares" do
      %w[provenance okf-docs].each do |fixture|
        app = app_for(dirs: fixture, keys: "5")
        declared = app.model.bundle.okf_version
        refute_nil declared, "#{fixture} should declare a version for this test to mean anything"

        assert_includes plain(frame_for(app, size: [ 130, 44 ])), "a legal OKF v#{declared} bundle",
          "#{fixture} declares #{declared} and the screen said otherwise"
      end
    end

    test "a bundle that declares no version is called conformant, not guessed at" do
      app = app_for(dirs: "minimal", keys: "5")
      skip "fixture declares a version" unless app.model.bundle.okf_version.nil?

      frame = plain(frame_for(app, size: [ 130, 44 ]))
      assert_includes frame, "a conformant bundle"
      refute_match(/legal OKF v/, frame)
    end

    test "health says which checks did not run rather than reporting over them" do
      app = app_for(dirs: "provenance", keys: "5")
      skipped = app.model.skipped_checks
      refute_empty skipped, "lint with no clock should skip the freshness pair"

      frame = plain(frame_for(app, size: [ 130, 44 ]))
      skipped.each do |check|
        assert_includes frame, check.to_s, "#{check} did not run and the screen did not say so"
      end
      assert_includes frame, "no clock supplied"
    end

    test "the posture rows carry okf's own numbers, and only where there are any" do
      app = app_for(dirs: "provenance", keys: "5")
      frame = plain(frame_for(app, size: [ 130, 44 ]))

      stats = app.model.lint.stats
      assert_includes frame, "trust unverified #{stats[:trust]["unverified"]}"
      assert_includes frame, "deprecated #{stats[:status]["deprecated"]}"

      # A tier the bundle has none of is dropped rather than clipped: the pane
      # holds a fixed width because its rows are short by construction. The
      # fixture has no zero-count tier, so the rule is asserted where it bites —
      # on a tally that does.
      assert_equal({ "human-reviewed" => 1 },
        OKF::TUI::Views.send(:posture_counts, "human-reviewed" => 1, "machine-confirmed" => 0))
    end

    test "a v0.1 bundle is offered no posture it never declared" do
      frame = plain(render(dirs: "okf-docs", keys: "5", size: [ 130, 44 ]))
      refute_includes frame, "posture", "a bundle with no §5 family got a posture section"
    end

    # ── graph: the two new facets ───────────────────────────────────────────

    test "the §5 facets are offered where the bundle has something to say" do
      offered = facet_values(app_for(dirs: "provenance", keys: "4"))
      assert_includes offered[:trust], "human-reviewed"
      assert_includes offered[:status], "deprecated"

      silent = facet_values(app_for(dirs: "okf-docs", keys: "4"))
      assert_empty silent[:trust], "a v0.1 bundle was offered a trust facet"
      assert_empty silent[:status], "a bundle with no declared status was offered a status facet"
    end

    test "the trust facet counts exactly the rows it selects" do
      # The bug okf names as "unverified 3 over two chipped cards": a facet whose
      # count includes rows it will not narrow to promises more than it returns.
      app = app_for(dirs: "provenance", keys: "4")

      app.graph_facet_entries.select { |entry| entry[:kind] == :facet && entry[:field] == :trust }.each do |facet|
        select_facet(app, :trust, facet[:value])
        assert_equal facet[:count], app.faceted_rows.length,
          "the trust facet `#{facet[:value]}` counted #{facet[:count]} and narrowed to #{app.faceted_rows.length}"
        clear_facet(app)
      end
    end

    test "the trust facet is narrower than the bundle-wide tally, and that is the point" do
      app = app_for(dirs: "provenance", keys: "4")
      facet = app.graph_facet_entries.find { |e| e[:kind] == :facet && e[:field] == :trust && e[:value] == "unverified" }
      refute_nil facet, "the fixture should carry unverified concepts whose tier is claimable"

      whole_bundle = app.model.lint.stats[:trust]["unverified"]
      assert_operator facet[:count], :<, whole_bundle,
        "the fixture must hold an unverified concept that declared nothing, or this proves nothing"
    end

    test "the status facet counts the effective value, exactly as --status narrows" do
      app = app_for(dirs: "provenance", keys: "4")

      app.graph_facet_entries.select { |entry| entry[:kind] == :facet && entry[:field] == :status }.each do |facet|
        # Agreement with okf rather than with a copy of its rule: ask RowFilter
        # the same question and compare, so okf changing the fold fails here.
        expected = app.model.rows.count { |row| OKF::Bundle::RowFilter.matches?(row, status: facet[:value]) }
        assert_equal expected, facet[:count], "the status facet `#{facet[:value]}` disagrees with RowFilter"

        select_facet(app, :status, facet[:value])
        assert_equal expected, app.faceted_rows.length
        clear_facet(app)
      end
    end

    test "the model's tier tally agrees with okf's own predicate" do
      model = app_for(dirs: "provenance", keys: "4").model
      claimed = model.rows.select { |row| OKF::Bundle::RowFilter.shows_trust?(row) }

      assert_equal claimed.length, model.tiers_of(model.rows).map { |_, count| count }.reduce(0, :+),
        "the tier tally covers a different set than okf is willing to claim"
      refute_equal model.rows.length, claimed.length,
        "the fixture must hold an unclaimable row, or the agreement is vacuous"
    end

    private

    def facet_values(app)
      entries = app.graph_facet_entries.select { |entry| entry[:kind] == :facet }
      { trust: entries.select { |e| e[:field] == :trust }.map { |e| e[:value] },
        status: entries.select { |e| e[:field] == :status }.map { |e| e[:value] } }
    end

    def select_facet(app, field, value)
      (app.graph_selectable.length + 1).times do
        row = app.graph_selected
        break if row && row[:kind] == :facet && row[:field] == field && row[:value] == value

        app.handle(DOWN)
      end

      selected = app.graph_selected
      assert_equal [ field, value ], [ selected[:field], selected[:value] ], "could not reach the #{field} facet #{value}"
      app.handle("\r")
    end

    def clear_facet(app)
      app.handle(OKF::TUI::App::ESCAPE)
      assert_nil app.graph_facet, "Esc did not clear the facet"
    end
  end
end
