# frozen_string_literal: true

require "test_helper"

module Integration
  # The graph: two selectable lists, and one Enter meaning two things because the
  # rows do.
  class GraphTest < OKF::TUI::TestCase
    test "it opens on a selectable row" do
      app = app_for(dirs: "okf-docs", keys: "4")
      assert_includes %i[facet concept], app.graph_selected[:kind]
    end

    test "Enter on a facet narrows the graph without leaving it" do
      app = app_for(dirs: "okf-docs", keys: "4")
      facet = app.graph_selected

      app.handle("\r")
      refute_nil app.graph_facet, "Enter on a facet did not set one"
      assert_equal :graph, app.view, "Enter on a facet left the graph view"
      assert_equal facet[:value], app.graph_facet[:value], "the facet should be the row that was selected"

      narrowed = app.faceted_rows
      assert_operator narrowed.length, :<, app.model.rows.length, "the facet did not narrow the concepts"

      # Narrowed means narrowed: every concept listed carries the facet.
      strays = narrowed.reject do |row|
        row[:type].to_s == facet[:value] || Array(row[:tags]).map(&:to_s).include?(facet[:value])
      end
      assert_empty strays, "#{strays.length} concepts survived a facet they do not carry"
    end

    test "the same key clears the facet, and so does Esc" do
      app = app_for(dirs: "okf-docs", keys: "4<enter>")
      refute_nil app.graph_facet

      app.handle("\r")
      assert_nil app.graph_facet, "selecting the facet again did not clear it"

      app.handle("\r")
      refute_nil app.graph_facet
      app.handle(OKF::TUI::App::ESCAPE)
      assert_nil app.graph_facet, "Esc did not clear the facet"
    end

    test "link degree is not recomputed under a facet" do
      app = app_for(dirs: "okf-docs", keys: "4<enter>")
      id = app.faceted_rows.first[:id]

      before = app.model.row_by_id(id)[:links_in]
      after = app.faceted_rows.find { |row| row[:id] == id }[:links_in]

      # The facet changes which concepts are drawn, not what they are worth.
      assert_equal before, after, "a facet should not change a concept's link degree"
    end

    test "Enter on a concept leaves for the file" do
      app = app_for(dirs: "okf-docs", keys: "4<tab>")
      target = app.graph_selected
      assert_equal :concept, target[:kind], "Tab should land on a concept row"

      app.handle("\r")
      assert_equal :browse, app.view, "Enter on a concept did not open browse"
      assert_equal target[:id], app.selected_row[:id], "browse opened the wrong concept"
    end

    test "the bars survive being selectable" do
      frame = plain(render(dirs: "okf-docs", keys: "4", size: [ 110, 20 ]))
      assert_includes frame, "█", "the distribution should still be drawn as bars"
    end
  end
end
