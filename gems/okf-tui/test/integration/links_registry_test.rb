# frozen_string_literal: true

require "test_helper"
require "json"

module Integration
  # Linked bundles in the bundles view (okf 2.2).
  #
  # okf's global registry can `link` another registry file, and that file's
  # bundles resolve into the set this view lists. They read like any other
  # bundle — which is right, since browsing one is browsing a bundle — but they
  # are **read-only**: the registry that owns them is another file, and okf
  # refuses every config write against one.
  #
  # So the four config keys have to refuse *before* the prompt. Letting the ask
  # through and surfacing okf's error afterwards makes a user type a new name and
  # confirm it before learning it could never land, and this view's own rule is
  # that a key which stops working says so rather than going quiet.
  class LinksRegistryTest < OKF::TUI::TestCase
    # A global registry holding `minimal`, linked to a second file holding
    # `conformant` under the link name `onm`. Yields the home directory.
    def with_link
      with_registry(:minimal) do |home, registry|
        target = File.join(home, "target.json")
        File.write(target, JSON.pretty_generate(
          "bundles" => [ { "slug" => "conformant", "path" => fixture(:conformant), "title" => "conformant" } ],
          "groups" => []
        ))
        registry.link("onm", target)
        yield home, target
      end
    end

    # okf owns the field, and this gem reads it. An agreement test rather than a
    # fixture: if okf renames `link` on a listing row, the entry silently stops
    # knowing it is linked and every refusal below quietly stops firing.
    test "the entry's link comes from okf's own listing row" do
      with_link do |home, _target|
        row = OKF::Registry.load(home: home).listing.find { |r| r[:slug] == "conformant" }

        assert_equal "onm", row[:link], "okf still names the field `link` on a listing row"
        app = app_for(home: home, keys: "1")
        assert_equal "onm", app.workspace.entry("conformant").link
        assert_nil app.workspace.entry("minimal").link, "a bundle the registry owns came through no link"
      end
    end

    # The fact goes in the detail pane, not on the row. The registry pane is 42
    # columns and already carries slug, count and `default`; a marker there would
    # clip on a narrow terminal, which this gem refuses to do. The detail is where
    # the other "what can I do with this one" lines already live.
    test "the detail pane says a linked bundle is read-only, and names the file" do
      with_link do |home, target|
        app = app_for(home: home, keys: "1")
        focus_conformant(app)
        frame = plain(frame_for(app))

        assert_match(/@conformant/, frame, "a linked bundle is a bundle; it lists")
        assert_match(/read-only — linked from @onm/, frame)
        # The path is on the next line and truncates to the pane, so the frame
        # cannot carry the whole of it — assert the value the line renders.
        assert_equal target, app.workspace.link_target("onm")
      end
    end

    test "rename, remove and default refuse a linked bundle before prompting" do
      with_link do |home, _target|
        %w[n x d].each do |key|
          app = app_for(home: home, keys: "1")
          focus_conformant(app)
          app.handle(key)

          message = plain(frame_for(app))
          assert_match(/@conformant is read-only — it comes from the linked registry @onm/, message,
            "`#{key}` has to say why, not open a prompt that cannot land")
          refute_match(/rename @conformant to:/, message, "`#{key}` opened no prompt")
        end
      end
    end

    test "a refused key changes nothing in either registry" do
      with_link do |home, target|
        before = File.read(target)
        app = app_for(home: home, keys: "1")
        focus_conformant(app)
        app.handle("x")
        app.handle("y") # the confirmation a real remove would have consumed

        assert_equal before, File.read(target), "the linked file is untouched"
        assert_equal %w[minimal conformant], OKF::Registry.load(home: home).slugs
      end
    end

    test "the keys still work on a bundle this registry owns" do
      with_link do |home, _target|
        app = app_for(home: home, keys: "1")

        app.handle("d")

        assert_match(/minimal/, plain(frame_for(app)))
        assert_equal "minimal", OKF::Registry.load(home: home).default.slug
      end
    end

    private

    # Move the bundles cursor onto the linked entry — it sorts after the ones the
    # registry owns, so one step down from the top.
    def focus_conformant(app)
      app.handle("\e[B") until app.selected_entry&.slug == "conformant"
    end
  end
end
