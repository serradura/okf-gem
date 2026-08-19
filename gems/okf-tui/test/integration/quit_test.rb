# frozen_string_literal: true

require "test_helper"

module Integration
  # Quitting is a chord. The single `q` it replaced ended the session on one
  # stray keystroke, with nothing to undo it.
  #
  # The check that carries the weight here is the *disarming* one: a chord that
  # arms and never lets go is the same bug wearing a second keystroke, and it
  # renders identically to the correct behaviour until you press the pair apart.
  class QuitTest < OKF::TUI::TestCase
    test "one q does not quit, and says what the second press would do" do
      app = app_for(dirs: "okf-docs", keys: "q")

      assert app.running?, "a single q ended the session"
      assert_includes plain(frame_for(app)), "press q again to quit",
        "an armed quit that says nothing is just a key that stopped working"
    end

    test "q q quits" do
      refute app_for(dirs: "okf-docs", keys: "qq").running?, "the chord did not quit"
    end

    test "a key between the two disarms" do
      app = app_for(dirs: "okf-docs", keys: "qjq")

      assert app.running?, "the arming survived another key, so q still quits on its own"
      assert_includes plain(frame_for(app)), "press q again to quit",
        "the second q should re-arm rather than quit"
    end

    test "ctrl-c still quits on its own" do
      refute app_for(dirs: "okf-docs", keys: OKF::TUI::App::CTRL_C).running?,
        "the escape hatch should not need confirming"
    end

    test "q typed into a filter is text, and does not arm" do
      app = app_for(dirs: "okf-docs", keys: "2/qq")

      assert app.running?, "a filter should own every printable key, q included"
      assert_equal "qq", app.filter, "the q keys should have reached the filter"
    end
  end
end
