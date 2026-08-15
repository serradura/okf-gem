# frozen_string_literal: true

require "test_helper"

module Integration
  # What the screen signals, and what `/` looks through.
  #
  # These are the things a screenshot of a healthy bundle cannot show: colour
  # only differs when something is wrong, and a filter that is silently ignored
  # still renders a perfectly good list.
  class SignalsTest < OKF::TUI::TestCase
    test "each standing has its own colour" do
      with_registry("okf-docs", "unhealthy", "malformed") do |home|
        app = app_for(home: home)

        expected = { "okf-docs" => :ok, "unhealthy" => :warn, "malformed" => :error }
        expected.each do |slug, standing|
          model = app.workspace.entry(slug).model
          assert_equal standing, OKF::TUI::Views.health_status(model), "@#{slug} reads as the wrong standing"
        end

        # A colour is only a signal if the three differ from each other.
        colours = expected.keys.map { |slug| OKF::TUI::Views.status_style(app.workspace.entry(slug).model)[:bg] }
        assert_equal 3, colours.uniq.length, "the three standings need three distinct colours"
      end
    end

    test "the health tab flags a bundle in trouble" do
      with_registry("okf-docs", "unhealthy", "malformed") do |home|
        app = app_for(home: home)

        app.workspace.switch("malformed")
        assert_includes tab_row(app), "health ✗", "the health tab does not flag a non-conformant bundle"

        app.workspace.switch("unhealthy")
        assert_includes tab_row(app), "health ▲", "the health tab does not flag lint warnings"

        app.workspace.switch("okf-docs")
        refute_match(/health [✗▲]/, tab_row(app), "the health tab flags a clean bundle")
      end
    end

    test "graph comes before health, and the number keys agree" do
      order = OKF::TUI::App::TABS.map(&:first)
      assert_operator order.index(:graph), :<, order.index(:health)

      OKF::TUI::App::KEY_VIEWS.each do |key, view|
        assert_equal order[key.to_i - 1], view, "key #{key} opens the wrong view"
      end
    end

    # Named rather than read from FILTERABLE_VIEWS: looping over the constant
    # under test means dropping a view from it silently tests one fewer view and
    # still passes.
    test "bundles, browse and graph each take a filter" do
      with_registry("okf-docs", "unhealthy") do |home|
        %i[bundles browse graph].each do |view|
          assert_includes OKF::TUI::App::FILTERABLE_VIEWS, view, "#{view} should take a filter"

          app = app_for(home: home, keys: OKF::TUI::App::KEY_VIEWS.key(view) + "/zzz-matches-nothing")

          narrowed =
            case view
            when :bundles then app.visible_entries
            when :browse then app.filtered_rows
            when :graph then OKF::TUI::Views.narrow(app.model.types + app.model.tags, app.filter)
            end

          assert_empty narrowed, "#{view}: the filter did not narrow anything"
        end
      end
    end

    test "a filter belongs to the view that took it" do
      with_registry("okf-docs", "unhealthy") do |home|
        app = app_for(home: home, keys: "1/okf<enter>")
        refute_empty app.filter, "Enter should keep the filter it accepted"

        app.handle("2")
        assert_empty app.filter, "the filter leaked into the next view"
      end
    end

    # ── the status line: asking, versus telling ──────────────────────────────

    test "a flash message is highlighted, and not in the colour that asks" do
      # It used to render :bright_black — the dimmest thing on screen, for the one
      # line that says what just happened. This is only a signal in colour, so a
      # piped test would have watched it silently go back to dim.
      with_colour do
        with_registry("okf-docs", "unhealthy") do |home|
          app = app_for(home: home, keys: "1")
          app.handle("d") # any registry write; the point is the line, not the key

          line = message_line(app)
          assert_match(/default/, plain(line), "the write should report itself on the status line")
          assert_match(/\e\[[0-9;]*46[;m]/, line,
            "a flash needs a background, or the eye has nothing to catch")
        end
      end
    end

    test "the line that asks and the line that tells wear different colours" do
      # Two states of one row. Told apart by colour before a word is read, which is
      # the whole reason the flash did not simply take the prompt's yellow.
      with_colour do
        with_registry("okf-docs", "unhealthy") do |home|
          app = app_for(home: home, keys: "1")
          app.handle("x") # asks before removing

          line = message_line(app)
          assert_match(/remove @/, plain(line), "x asks first")
          assert_match(/\e\[[0-9;]*43[;m]/, line, "a question stays yellow")
          refute_match(/\e\[[0-9;]*46[;m]/, line, "and must not borrow the flash's colour")
        end
      end
    end

    private

    # The status row, raw — the escapes are the subject here, so this is one of the
    # few places that must not go through #plain. Found by position rather than by
    # its text: a frame paints the same words in a dozen places, and matching them
    # picked a bundle row on the first run of this.
    def message_line(app)
      frame_for(app).lines[-2].to_s
    end

    def with_colour
      previous = OKF::TUI::Ui::PASTEL
      OKF::TUI::Ui.send(:remove_const, :PASTEL)
      OKF::TUI::Ui.const_set(:PASTEL, Pastel.new(enabled: true))
      yield
    ensure
      OKF::TUI::Ui.send(:remove_const, :PASTEL)
      OKF::TUI::Ui.const_set(:PASTEL, previous)
    end

    def tab_row(app, width = 120)
      plain(OKF::TUI::Views.tabs(app, width))
    end
  end
end
