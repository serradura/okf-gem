# frozen_string_literal: true

require "test_helper"
require "pty"
require "timeout"

module Integration
  # `okf tui` in a real process, through a real pseudo-terminal.
  #
  # Every other test calls App#handle directly and never opens a terminal, so
  # none of them can catch a broken key loop, a raw-mode failure, or a verb that
  # will not boot. This can: real keypresses, real exit status.
  #
  # It spawns okf's executable rather than one of this gem's, because this gem
  # has none — the plugin seam is the only entry point. That makes this the one
  # test that proves the *whole* path a user actually walks: okf boots, misses
  # `tui` among its built-ins, discovers `okf/plugin.rb` on the load path,
  # registers the verb, and hands it a real terminal. Every other plugin test
  # drives the dispatcher in-process, which skips process boot and discovery
  # both.
  class TerminalTest < OKF::TUI::TestCase
    # The okf the bundle resolved, asked of RubyGems rather than guessed from a
    # relative path: it is a path source in the monorepo and a real gem
    # elsewhere, and this has to keep working either way.
    OKF_EXE = Gem.bin_path("okf", "okf")
    IDLE = 0.7   # a gap this long means the frame is fully painted
    BOOT = 20    # the first byte waits on a Bundler setup and a pile of requires
    BUDGET = 90  # the whole run; the test must never be the thing that hangs

    # [ keys to send, a string that must appear in the frame that follows ]
    SCRIPT = [
      [ "",         "registry" ],      # opens on the bundle list
      [ "\r",       "concepts" ],      # Enter opens the active bundle
      [ "4",        "connectivity" ],
      [ "\r",       "narrowed to" ],   # Enter on a facet narrows the graph
      # One control key per step: two in a single write can reach the reader as
      # one keypress, which is a race the test would lose only sometimes.
      [ "\t",       "connectivity" ], # Tab moves to the concept list
      [ "\r",       "opened" ],       # Enter on a concept opens the file
      [ "5",        "conformance" ],
      [ "6",        "Navigation" ],
      [ "3/orphan", "to search" ],     # typed, deliberately not searched yet
      [ "\r",       "across" ],        # Enter submits it — across the bundles
      [ "\e",       "to edit" ],       # Esc releases the field...
      [ "3",        "search" ],        # ...and stays in search, not tab 1
      [ "1",        "registry" ],
      [ "x",        "remove @" ],      # a confirm prompt...
      [ "n",        "cancelled" ]      # ...answered no: nothing is written
    ].freeze

    test "it boots a pty, walks every view, and quits cleanly" do
      with_registry("okf-docs", "unhealthy") do |home|
        before = File.read(OKF::Registry.path(home: home))
        painted = 0

        reader, writer, pid = PTY.spawn(
          # TERM too: tty-cursor shells out to `tput`, and a container or a CI
          # runner without one paints nothing at all. OKF_HOME is named here
          # rather than left to inheritance: it is the only lever on which
          # registry the child reads, so the one thing this test must not do is
          # let it reach the real ~/.okf.
          { "LINES" => "40", "COLUMNS" => "120", "TERM" => "xterm", "OKF_HOME" => home },
          RbConfig.ruby, OKF_EXE, "tui"
        )

        # The environment names a size, but TTY::Screen asks the pty itself first;
        # an unsized pty reports nothing and the app paints an empty frame.
        reader.winsize = [ 40, 120 ]

        begin
          Timeout.timeout(BUDGET) do
            SCRIPT.each do |keys, expected|
              writer.write(keys) unless keys.empty?
              frame = settle(reader)
              painted += frame.bytesize
              assert_includes plain(frame), expected, "after #{keys.inspect}"
            end

            # Two, not one: quitting is a chord now, and a real process on a real
            # pty is the only place that proves the pair survives a live
            # keypress reader.
            writer.write("qq")
            settle(reader)
          end
        rescue Errno::EIO
          nil # a clean quit closes the pty, which surfaces here
        end

        reap(pid)
        assert_operator painted, :>, 0, "the app painted nothing"
        assert_equal before, File.read(OKF::Registry.path(home: home)), "the run wrote to the registry"
      end
    end

    private

    # Read until the child goes quiet. IO.select reports readiness rather than
    # racing a timer against a blocking read.
    #
    # The generous wait lasts until a painted *frame* arrives, not until the
    # first byte. The app hides the cursor before it does any work, so the first
    # bytes land immediately and the real boot — a Bundler setup, a pile of gem
    # loads, and reading every bundle — happens after them. Switching to the
    # short gap on the first byte declares an app that has not painted yet
    # "settled", which is exactly what it did on the 2.4 floor.
    #
    # A frame always contains newlines; the escape sequences before it do not.
    def settle(reader)
      buffer = +""

      loop do
        # IO.select, not wait_readable: this waits on a pty the test owns, and
        # there is no fiber scheduler in play.
        break unless IO.select([ reader ], nil, nil, buffer.include?("\n") ? IDLE : BOOT) # rubocop:disable Lint/IncompatibleIoSelectWithFiberScheduler

        begin
          buffer << reader.readpartial(64 * 1024)
        rescue EOFError, Errno::EIO
          break
        end
      end

      buffer
    end

    def reap(pid)
      status = Timeout.timeout(5) { Process.waitpid2(pid).last }
      assert_equal 0, status.exitstatus, "`okf tui` exited badly"
    rescue Timeout::Error
      Process.kill("KILL", pid)
      flunk "`okf tui` did not exit on 'q'"
    rescue Errno::ECHILD
      nil
    end
  end
end
