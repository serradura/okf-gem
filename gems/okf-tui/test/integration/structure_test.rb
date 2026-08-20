# frozen_string_literal: true

require "test_helper"
require "okf/cli"
require "json"

module Integration
  # The two structural measurements, on the health view: hubs with their inbound
  # breakdown (okf 1.10's `graph --hubs`) and per-directory traffic with cohesion
  # (okf 1.12's `graph --traffic`).
  #
  # They live in health rather than in a view of their own because health is
  # already the page of judgements about a bundle — conformance, then curation,
  # and now structure. Every number here is okf's; these tests pin that by asking
  # okf the same question and comparing, rather than by re-asserting a formula the
  # TUI would then own a second copy of.
  class StructureTest < OKF::TUI::TestCase
    # ── hubs ─────────────────────────────────────────────────────────────────

    test "the hubs are okf's hubs, in okf's order" do
      model = OKF::TUI::Model.new(fixture(:nested))

      assert_equal okf_json(:nested, "--hubs")["hubs"].map { |hub| [ hub["id"], hub["inbound"] ] },
        model.hubs.map { |hub| [ hub[:id], hub[:inbound] ] }
    end

    test "the health view shows where a hub's inbound links come from" do
      frame = plain(render(dirs: [ :nested ], keys: "5"))

      assert_match(/hubs — where their inbound links come from/, frame)
      # The number alone is already in the graph view; the home dir is what makes
      # this a judgement rather than a repeat.
      assert_match(%r{platform/data/warehouse\s+←3\s+in platform}, frame)
    end

    test "a hub drawing its majority from one foreign dir is told which" do
      # @nested's vocabulary/terms takes 2 of its 3 inbound links from platform/,
      # so platform is the better home it has already named.
      frame = plain(render(dirs: [ :nested ], keys: "5"))

      assert_match(%r{vocabulary/terms.*mostly from platform}, frame)
    end

    test "a scattered foreign majority is reported as a count, not a destination" do
      # platform/data/warehouse takes 2 of 3 from outside platform/, but from two
      # different dirs — so there is no single better home, and naming one on a
      # plurality would be advice the evidence does not support.
      frame = plain(render(dirs: [ :nested ], keys: "5"))

      assert_match(%r{platform/data/warehouse.*2 of 3 from elsewhere}, frame)
      refute_match(%r{platform/data/warehouse.*mostly from}, frame)
    end

    test "a hub whose links come from home is not flagged" do
      frame = plain(render(dirs: [ :nested ], keys: "5"))
      row = frame.lines.find { |line| line.include?("platform/services/worker") }

      refute_nil row, "the fixture should have a hub linked only from its own dir"
      refute_includes row, "▲", "nothing to answer for, so no flag"
      refute_includes row, "elsewhere"
    end

    test "a bundle nothing links to says so rather than showing an empty section" do
      frame = plain(render(dirs: [ :minimal ], keys: "5"))

      assert_match(/nothing is linked to yet/, frame)
    end

    # ── dir traffic ──────────────────────────────────────────────────────────

    test "the traffic figures are okf's, to the number" do
      model = OKF::TUI::Model.new(fixture(:nested))
      mine = model.dir_traffic.map { |row| [ row[:dir], row[:internal], row[:out], row[:in], row[:cohesion] ] }
      theirs = okf_json(:nested, "--traffic")["dirs"]
               .map { |row| [ row["dir"], row["internal"], row["out"], row["in"], row["cohesion"] ] }

      # Compared as sets: okf's --json emits skeleton order, while its human table
      # sorts by cohesion — which is the order asserted separately below.
      assert_equal theirs.sort_by(&:first), mine.sort_by(&:first)
    end

    test "the rows lead with the directories that have a case to answer" do
      model = OKF::TUI::Model.new(fixture(:nested))
      cohesions = model.dir_traffic.map { |row| row[:cohesion] }

      assert_equal cohesions.compact.sort, cohesions.compact,
        "cohesion ascending, so the low ones are not buried under the rows nobody needed"
      assert_nil cohesions.last, "a dir with no traffic at all sorts last — it has nothing to answer for"
    end

    test "a dir with no traffic reads as a dash, not as 0%" do
      # @nested's platform/ holds no concepts of its own, so it carries no links
      # either way. 0% would claim it failed a measurement it never took.
      frame = plain(render(dirs: [ :nested ], keys: "5<tab>"))
      row = frame.lines.find { |line| line =~ /^\s*║?\s*platform\s{2,}/ }

      refute_nil row, "platform/ should have a traffic row"
      assert_includes row, "—"
      refute_includes row, "0%"
    end

    test "the traffic section matches okf's own human table, row for row" do
      # The strongest form of the agreement: the same directories, in the same
      # order, with the same four numbers — read off the rendered frame.
      frame = plain(render(dirs: [ :nested ], keys: "5<tab>"))
      rendered = frame.lines.map { |line| line.gsub(/[║│]/, "").strip }

      expected_rows = okf_traffic_rows(:nested)
      # Without this the loop below is vacuous: a parse that silently matched
      # nothing would assert nothing and report success.
      assert_equal 5, expected_rows.length,
        "okf's traffic table should have parsed into 5 rows, got #{expected_rows.inspect}"

      expected_rows.each do |label, internal, out, into, cohesion|
        expected = /#{Regexp.escape(label)}\s+#{internal}\s+#{out}\s+#{into}\s+#{Regexp.escape(cohesion)}/
        assert rendered.any? { |line| line =~ expected },
          "no rendered row matched okf's #{label}: #{internal} #{out} #{into} #{cohesion}"
      end
    end

    test "a single-directory bundle is told there is nothing to weigh" do
      # @minimal is one flat directory: every row would compare it to itself.
      frame = plain(render(dirs: [ :minimal ], keys: "5<tab>"))

      assert_match(/nothing to weigh it against/, frame)
    end

    test "the root reads as (root) here too" do
      frame = plain(render(dirs: [ :nested ], keys: "5<tab>"))

      assert_match(/\(root\)\s+0\s+3\s+1/, frame, "`.` is the stored spelling, not the label")
    end

    # ── the arcs ─────────────────────────────────────────────────────────────
    #
    # The cohesion table says how much of a directory's traffic stays home; the arcs
    # say where the rest goes. Both halves of `graph --traffic`.

    test "the arcs are okf's arcs, above okf's own fitted cut" do
      model = OKF::TUI::Model.new(fixture(:nested))
      arcs, cut, total = model.dir_arcs
      skeleton = model.bundle.skeleton

      assert_equal skeleton.suggested_cut, cut,
        "the cut is fitted to the bundle by okf — ten bundles ranged from 2 arcs to 136 at a fixed one"
      assert_equal skeleton.arcs.length, total
      assert_equal OKF::Bundle::Skeleton.arcs_above(skeleton.arcs, cut).length, arcs.length
    end

    test "narrowing the arcs never moves the cohesion" do
      # okf is explicit that the cut narrows the *picture* and cohesion is computed
      # over every arc regardless. Showing the two together is only safe if that
      # holds, so it is asserted rather than assumed.
      # @okf-docs is the only fixture whose arcs actually narrow (20 arcs, cut 7,
      # nine survive) — on the others the check would prove nothing.
      model = OKF::TUI::Model.new(fixture("okf-docs"))
      before = model.dir_traffic.map { |row| [ row[:dir], row[:cohesion] ] }
      arcs, = model.dir_arcs

      refute_equal model.bundle.skeleton.arcs.length, arcs.length,
        "this fixture should actually be narrowed, or the check proves nothing"
      assert_equal before, model.dir_traffic.map { |row| [ row[:dir], row[:cohesion] ] }
    end

    test "the arcs section says it is narrowed, and by how much" do
      # Tall enough to reach the arcs: the health page is built whole and scrolled,
      # and on this bundle they sit below a default terminal's fold.
      frame = plain(render(dirs: [ "okf-docs" ], keys: "5<tab>", size: [ 100, 60 ]))
      arcs, cut, total = OKF::TUI::Model.new(fixture("okf-docs")).dir_arcs

      assert_match(/#{arcs.length} of #{total} arcs at weight #{cut} or more/, frame,
        "a silently shortened list reads as a complete one")
    end

    test "a bundle with no cross-directory links shows no arcs section" do
      # On the standing pane, where the arcs would be — a refutation read off the
      # findings pane would pass because the section lives elsewhere entirely.
      frame = plain(render(dirs: [ :minimal ], keys: "5<tab>"))

      assert_match(/dir traffic/, frame, "the pane that would carry them")
      refute_match(/arcs at weight/, frame, "nothing to draw, so no heading over nothing")
    end

    # ── the tallies the TUI computes itself ──────────────────────────────────

    test "the type and tag counts agree with okf's own indexes" do
      # These are the one place the TUI counts rather than asks: okf's type_index and
      # tag_index are whole-bundle inverted indexes, and the graph view needs counts
      # *within the facet in force*, which okf has no API for. So the counts are
      # derived here — and pinned against okf's, because a derivation that drifts
      # from the library is exactly what constraint 1 exists to prevent.
      model = OKF::TUI::Model.new(fixture(:nested))
      graph = model.bundle.graph(minimal: true)

      assert_equal graph.type_index.map { |type, ids| [ type, ids.length ] }.sort,
        model.types.sort, "types"
      assert_equal graph.tag_index.map { |tag, ids| [ tag, ids.length ] }.sort,
        model.tags.sort, "tags"
    end

    test "a blank type is left out of the tally, as §9.2 says it should be" do
      # @malformed carries a concept whose type is whitespace. okf's index drops it
      # too, so agreement is the check — a bar with no label would be the tell.
      model = OKF::TUI::Model.new(fixture(:malformed))
      graph = model.bundle.graph(minimal: true)

      assert_equal graph.type_index.map { |type, ids| [ type, ids.length ] }.sort,
        model.types.sort
      refute_includes model.types.map(&:first), "", "a blank type must not draw a bar with no label"
      assert_includes model.types.map(&:first), "Untyped", "it gets okf's name instead"
    end

    # ── the whole page ───────────────────────────────────────────────────────

    # A terminal short enough that either pane must overflow whatever okf puts in
    # it. Both of these used to prove overflow by leaning on the fixture producing
    # lint findings — which the okf *checkout* reports and the released okf does
    # not, so they passed here and failed on CI. The scroll is a property of the
    # pane, so the premise should be geometry and never okf's analysis.
    SHORT = [ 100, 12 ].freeze

    test "each pane scrolls past its own sections" do
      app = app_for(dirs: [ "okf-docs" ], keys: "5", size: SHORT)
      top = plain(frame_for(app, size: SHORT))
      assert_match(%r{findings 1-\d+/\d+}, top,
        "the pane has to overflow, or the scroll below proves nothing")

      6.times { app.handle(OKF::TUI::App::DOWN) }
      refute_match(%r{findings 1-\d+/\d+}, plain(frame_for(app, size: SHORT)),
        "the findings did not move")

      app.handle(OKF::TUI::App::TAB)
      assert_match(%r{standing 1-\d+/\d+}, plain(frame_for(app, size: SHORT)),
        "Tab reaches the standing pane, and finds it at its own top")

      app.handle("G")
      assert_match(/stats/, plain(frame_for(app, size: SHORT)),
        "and its own end is reachable, not the one the findings are at")
    end

    test "the two panes keep their places apart" do
      # One shared offset would drag the short pane to its end and hold it there
      # while the long one scrolled, which is the reason each owns a scroll.
      app = app_for(dirs: [ "okf-docs" ], keys: "5", size: SHORT)
      6.times { app.handle(OKF::TUI::App::DOWN) }
      findings = plain(frame_for(app, size: SHORT))
      refute_match(%r{findings 1-\d+/\d+}, findings, "the findings did not move")

      app.handle(OKF::TUI::App::TAB)
      assert_match(%r{standing 1-\d+/\d+}, plain(frame_for(app, size: SHORT)),
        "the standing pane is still at its own top")

      app.handle(OKF::TUI::App::TAB)
      assert_equal findings, plain(frame_for(app, size: SHORT)),
        "and the findings came back where they were left"
    end

    test "a wide terminal shows both panes at once" do
      frame = plain(render(dirs: [ "okf-docs" ], keys: "5", size: [ 140, 40 ]))

      assert_match(/hubs —/, frame, "the findings")
      assert_match(/dir traffic/, frame, "and the standing, without a keystroke between them")
    end

    private

    def okf_json(fixture_name, flag)
      out = StringIO.new
      status = OKF::CLI.start([ "graph", fixture(fixture_name), flag, "--json" ],
        out: out, err: StringIO.new)
      assert_equal 0, status, "okf graph #{flag} should succeed on the fixture"

      JSON.parse(out.string)
    end

    # okf's *human* traffic table, parsed back into rows — the order the TUI sorts
    # into, and the labels it prints, both come from here.
    def okf_traffic_rows(fixture_name)
      out = StringIO.new
      OKF::CLI.start([ "graph", fixture(fixture_name), "--traffic" ], out: out, err: StringIO.new)

      cells = out.string.lines.map { |line| line.split(/\s{2,}/).map(&:strip).reject(&:empty?) }
      # The data rows: six columns, with a concept count in the second.
      cells.select { |row| row.length == 6 && row[1] =~ /\A\d+\z/ }
           .map { |row| [ row[0], row[2], row[3], row[4], row[5] ] }
    end
  end
end
