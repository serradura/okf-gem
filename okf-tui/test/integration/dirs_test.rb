# frozen_string_literal: true

require_relative "../test_helper"
require "okf/cli"
require "json"

module OKF
  module TUI
    # Directories, as okf defines them now.
    #
    # okf 1.11 made the full directory path a first-class dimension and 1.12
    # renamed the first-segment rollup `area` → `top_dir`, so "how many
    # directories does this bundle have?" has one right answer and the TUI has to
    # give okf's. The `nested` fixture is the only one that can tell the two
    # apart: every other fixture is one level deep, where a full path and its
    # first segment are the same string, so an assertion against them passes
    # whichever field the code reads.
    class DirsTest < TestCase
      # What okf itself says about the fixture, so these tests fail when the TUI
      # disagrees with the library rather than when a fixture is edited.
      #   dirs: . history platform platform/data platform/services vocabulary
      #   top_dirs: (root) platform vocabulary
      NESTED_DIRS = 6
      NESTED_TOP_DIRS = 3

      def nested_model
        Model.new(fixture("nested"))
      end

      # The facet rows of one field, as [ value, count ] pairs.
      def facets(app, field)
        app.graph_facet_entries
           .select { |entry| entry[:kind] == :facet && entry[:field] == field }
           .map { |entry| [ entry[:value], entry[:count] ] }
      end

      # Put the cursor on a facet row and press Enter, the way a user reaches it.
      # Bounded by the row count: a `while` waiting on the code under test turns a
      # regression into a hung suite instead of a failure.
      def select_facet(app, field, value)
        entries = app.graph_facet_entries
        index = entries.index { |entry| entry[:field] == field && entry[:value] == value }
        refute_nil index, "no #{field} facet for #{value.inspect} — offered: #{facets(app, field).inspect}"

        app.instance_variable_set(:@cursor, index)
        app.handle("\r")
      end

      # okf's own answer, asked of okf: the `subtree` column of `okf dirs --json`,
      # which okf defines as "exactly what --dir on the row returns". Comparing the
      # facet against this pins agreement on *results* rather than duplicating the
      # rule and asserting the duplicate.
      #
      # Zero-subtree dirs are dropped, matching the facet: a row that narrows to
      # nothing is not a facet worth offering.
      def okf_subtree_counts(name)
        out = StringIO.new
        status = OKF::CLI.start([ "dirs", fixture(name), "--json" ], out: out, err: StringIO.new)
        assert_equal 0, status, "okf dirs should succeed on the fixture"

        JSON.parse(out.string)["dirs"]
            .reject { |row| row["subtree"].zero? }
            .map { |row| [ row["dir"], row["subtree"] ] }
      end

      test "the fixture is the only one that can tell dir from top_dir" do
        model = nested_model

        assert_equal NESTED_DIRS, model.bundle.directories.length,
          "okf's own count moved — retune this test against it, do not paper over it"
        refute_equal NESTED_DIRS, NESTED_TOP_DIRS,
          "a fixture where the two agree proves nothing about which field is read"
      end

      test "the model counts directories the way okf counts them" do
        assert_equal NESTED_DIRS, nested_model.dirs.length
      end

      test "an intermediate directory holding no concepts still counts" do
        # `platform/` holds only an index.md and two subdirectories. It is a
        # directory `--dir platform` addresses, so it is one the TUI must count —
        # reading the catalog instead drops it, which is the disagreement okf
        # 1.13.0 fixed inside the library.
        assert_includes nested_model.dirs, "platform"
      end

      test "a directory whose only file is its log still counts" do
        # okf 1.13.0's second pass: a log-only directory was invisible to the
        # directory set, so the `root` alias beat a real `root/` one file kind over.
        assert_includes nested_model.dirs, "history"
      end

      test "the header counts directories, not first path segments" do
        with_registry(:nested) do |home|
          frame = plain(render(home: home, keys: ""))

          assert_match(/#{NESTED_DIRS} dirs/, frame)
          refute_match(/#{NESTED_TOP_DIRS} dirs/, frame,
            "counting first path segments is what reading the renamed field gave")
          refute_match(/\bareas\b/, frame,
            "`area` is not okf's word for this — 1.12.0 renamed the rollup it named")
        end
      end

      # ── the dir facet ──────────────────────────────────────────────────────
      #
      # okf 1.11 made the full directory path a filter on six verbs and 1.12
      # deprecated the first-segment `--area` for "losing every level below it".
      # The graph view offered type and tag only, so the TUI could narrow by
      # neither the dimension okf now leads with nor the one it deprecated.

      test "dirs are offered as a third facet, with okf's subtree counts" do
        app = app_for(dirs: [ :nested ], keys: "4")
        dirs = facets(app, :dir)

        refute_empty dirs, "a nesting bundle should offer a dirs facet"
        assert_equal okf_subtree_counts("nested"), dirs,
          "the facet counts must be the subtree counts okf's own `dirs` view prints"
      end

      # The point of the whole thing: narrowing by a directory has to reach what
      # lives below it, which is okf's one rule for --dir. A facet matching only
      # its own level would be the `--area` rollup okf deprecated.
      test "narrowing by a dir reaches everything beneath it" do
        app = app_for(dirs: [ :nested ], keys: "4")
        select_facet(app, :dir, "platform")

        ids = app.faceted_rows.map { |row| row[:id] }.sort

        assert_equal %w[platform/data/warehouse platform/services/api platform/services/worker], ids,
          "platform/ has no concepts of its own — every one of these is a level or more below it"
      end

      test "a deeper dir narrows further" do
        app = app_for(dirs: [ :nested ], keys: "4")
        select_facet(app, :dir, "platform/services")

        assert_equal %w[platform/services/api platform/services/worker],
          app.faceted_rows.map { |row| row[:id] }.sort
      end

      # okf's rule has no special case for the root, and the consequence is easy to
      # get wrong the other way: `.` selects what lives *directly* in the root, not
      # the whole bundle. okf's own subtree for `.` on this fixture is 1, of 5.
      test "the root dir is the root alone, not the whole bundle" do
        app = app_for(dirs: [ :nested ], keys: "4")
        select_facet(app, :dir, ".")

        assert_equal %w[overview], app.faceted_rows.map { |row| row[:id] },
          "`.` is the root by itself — everything below it has its own dir"
      end

      test "the root facet is labelled the way okf labels it" do
        frame = plain(render(dirs: [ :nested ], keys: "4"))

        assert_match(/\(root\)/, frame, "okf prints `(root)` for a reader; `.` is the stored spelling")
      end

      test "selecting the facet in force clears it, like every other facet" do
        app = app_for(dirs: [ :nested ], keys: "4")
        select_facet(app, :dir, "platform")
        assert app.facet_active?(:dir, "platform")

        # Re-find the row rather than pressing Enter again at the same index:
        # narrowing rebuilt the list, so the old position is a different facet now.
        select_facet(app, :dir, "platform")

        refute app.facet_active?(:dir, "platform")
        assert_equal 5, app.faceted_rows.length, "clearing should give the whole bundle back"
      end

      test "Esc clears a dir facet, the way it clears the others" do
        app = app_for(dirs: [ :nested ], keys: "4")
        select_facet(app, :dir, "platform/services")

        app.handle(OKF::TUI::App::ESCAPE)

        assert_nil app.graph_facet
        assert_equal 5, app.faceted_rows.length
      end

      test "a directory holding nothing is not offered as a facet" do
        # `history/` is a real directory — okf counts it and `--dir history`
        # addresses it — but its only file is a log, so as a facet it is a row that
        # narrows to nothing.
        app = app_for(dirs: [ :nested ], keys: "4")

        assert_includes nested_model.dirs, "history", "okf still counts it"
        refute_includes facets(app, :dir).map(&:first), "history",
          "but a facet that selects no concept is a dead end"
      end

      test "a bundle that does not nest is offered no dirs section" do
        # conformant/ has two directories (datasets, tables) and is still one level
        # deep, so every dir facet would say what a top-level rollup says — and a
        # rollup is what okf deprecated `--area` for being. The gate is nesting, not
        # a count of directories.
        app = app_for(dirs: [ :conformant ], keys: "4")

        assert_equal 2, okf_subtree_counts("conformant").length,
          "this fixture has two dirs, so a count-based gate would have shown them"
        assert_empty facets(app, :dir),
          "a bundle one level deep should be offered no dirs facet at all"
        refute_match(/▌ dirs/, plain(frame_for(app)), "and no heading over nothing")
      end

      test "the dir facet composes with a type facet" do
        app = app_for(dirs: [ :nested ], keys: "4")
        select_facet(app, :dir, "platform")

        # Within platform/, the types tally is counted over the narrowed set.
        types = facets(app, :type)

        assert_equal [ [ "Service", 2 ], [ "Dataset", 1 ] ], types,
          "the facet in force should narrow what the other sections count"
      end

      test "the bundle detail pane reports okf's directory count" do
        with_registry(:nested) do |home|
          # `1` is the bundles view, which is the one carrying the detail pane.
          frame = plain(render(home: home, keys: "1"))

          assert_match(/dirs\s+#{NESTED_DIRS}\b/, frame)
          refute_match(/\bareas\b/, frame)
        end
      end
    end
  end
end
