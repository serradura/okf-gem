# frozen_string_literal: true

require "test_helper"

module Integration
  # Following a link out of a document — the graph the bundle already has, walked
  # a page at a time instead of read as a ranking.
  #
  # Named, not counted: `follow_to("cli")` is a statement about which link was
  # taken, where `f<down><enter>` would be a guess about the order okf extracted
  # them in.
  class LinksTest < OKF::TUI::TestCase
    test "a document offers what it links to, as what is at the far end" do
      app = app_for(dirs: "okf-docs", keys: "2f")

      assert app.following?, "f should open the picker"
      links = app.follow_links
      refute_empty links, "the bundle index links to its areas and its loose concepts"

      concept = links.find { |link| link[:kind] == :concept }
      assert concept, "the root index links at concepts"
      refute_equal concept[:target], concept[:label],
        "a link should read as its title, not as the path it was written with"
    end

    # The case that would have been silently empty. okf resolves a directory
    # target to nil — correctly, since `format/` is not a graph edge — but that
    # is exactly how every index.md points at its areas, so the root index would
    # have been the one page in the bundle with nothing to follow.
    test "the bundle index follows its area links to their indexes" do
      links = app_for(dirs: "okf-docs", keys: "2f").follow_links
      areas = links.select { |link| link[:kind] == :reserved }.map { |link| link[:target] }

      refute_empty areas, "the root index should follow `format/` to format/index.md"
      assert_includes areas, "format/index.md"
      assert_includes links.map { |link| link[:label] }, "format",
        "a nested index reads as its area — that is what the link meant"
    end

    test "a digit follows that link, and the picker owns the digits while open" do
      app = app_for(dirs: "okf-docs", keys: "2f2")

      assert_equal :browse, app.view,
        "2 should have picked a link, not switched to the browse-view number"
      refute app.following?, "following a link closes the picker"

      entry = app.selected_browse_entry
      assert entry, "following a link should select something"
      assert_equal :concept, entry[:kind]
    end

    test "following an area link lands on that index" do
      app = app_for(dirs: "okf-docs", keys: "2f4")
      entry = app.selected_browse_entry

      assert entry, "the picker should have opened something"
      assert_equal :reserved, entry[:kind], "an area link lands on the area's index.md"
      assert_equal "format/index.md", entry[:path]
    end

    test "backspace returns to where the jump started" do
      before = app_for(dirs: "okf-docs", keys: "2")
      after = app_for(dirs: "okf-docs", keys: "2f2" + OKF::TUI::App::DELETE)

      assert_equal 0, after.trail_depth, "the trail should be spent"
      assert_equal before.selected_browse_entry, after.selected_browse_entry,
        "back should land on the document the link was followed out of"
    end

    # The trail is pushed inside open_concept, so the two jumps that already
    # existed became reversible without either of them being touched.
    test "opening a search hit is reversible too" do
      app = app_for(dirs: "okf-docs", keys: "3/registry<enter><enter>")

      assert_equal :browse, app.view, "a hit should open in browse"
      assert_operator app.trail_depth, :>, 0, "opening a hit should be undoable"

      app.handle(OKF::TUI::App::DELETE)
      assert_equal :search, app.view, "back should return to the search that found it"
    end

    test "esc puts the body back exactly where it was" do
      read = frame_for(app_for(dirs: "okf-docs", keys: "2<tab>JJJ"))
      reopened = frame_for(app_for(dirs: "okf-docs", keys: "2<tab>JJJf<esc>"))

      assert_equal read, reopened,
        "opening the picker and closing it should cost neither the pane nor its scroll"
    end

    # Esc peels the innermost layer, and the picker is now the innermost one: a
    # find that was running has to survive it, or opening the links costs the
    # find the way it once cost the file being read.
    test "esc closes the picker without ending a running find" do
      app = app_for(dirs: "okf-docs", keys: "2<tab>/registry<enter>f<esc>")

      refute app.following?, "esc should close the picker"
      assert_equal "registry", app.find, "the find should still be lit"
    end

    test "a link with nothing behind it is offered as not written yet" do
      with_registry("unhealthy") do |home|
        app = app_for(home: home, keys: "2/linked<enter>")
        app.handle("f")

        missing = app.follow_links.find { |link| link[:kind] == :missing }
        assert missing, "the fixture links at a file that does not exist"

        app.handle("\r")

        assert_includes plain(frame_for(app)), "is not in this bundle yet",
          "a broken link is knowledge not written yet, not an error to raise"
        assert app.following?,
          "a dead link means the reader has not finished choosing — the picker should stay open"
      end
    end

    test "a document with no links says so rather than opening an empty picker" do
      app = app_for(dirs: "minimal", keys: "2")
      app.handle("f")

      refute app.following?, "an empty picker is a dead end with no way out marked"
      assert_includes plain(frame_for(app)), "no links in this document"
    end
  end
end
