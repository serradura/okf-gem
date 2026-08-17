# frozen_string_literal: true

require "test_helper"

# `State` is what both the banner and `okf pro state` read, and its contract is
# a cost rather than a shape: **cheap by default**. The default payload reads
# `board.md`, `log.md` and two directory globs, and parses NO concept — because
# the banner runs at every session start whether anyone asks or not, and a
# banner that parsed the corpus would be a tax on opening a terminal.
#
# `--full` is where `Bundle::Reader.read` lives, once, shared by all three of
# the things that need it.
class StateTest < OKF::Pro::TestCase
  TODAY = Date.new(2026, 8, 17)

  def populated(b)
    b.concept("reference/pricing.md", type: "Briefing",
      generated: { by: "claude", at: "2026-08-01" })
    b.write("projects/alpha/index.md", "# Alpha\n\nOpen.\n")
    b.in_flight("[/projects/alpha/](/projects/alpha/index.md) — call them")
    b.inbox("2026-08-13 — an old capture", "2026-08-16 — a newer one")
    b.board_lines("Waiting", "Landlord — chase 2026-08-14")
    b.board_lines("To read", "[/reference/pricing.md] — unread")
  end

  # The read is stubbed to raise, so "did not parse the corpus" is proven by
  # the code not reaching it rather than by a timing guess.
  def with_corpus_unreadable
    reader = ::OKF::Bundle::Reader
    original = reader.method(:read)
    reader.define_singleton_method(:read) { |*| raise "the corpus was parsed" }
    yield
  ensure
    reader.define_singleton_method(:read, original)
  end

  test "the default payload parses no concept" do
    with_bundle do |b|
      populated(b)
      path = b.bundle_path

      with_corpus_unreadable do
        payload = OKF::Pro::State.call(path, today: TODAY)

        assert_equal 1, payload["board"]["in flight"]
      end
    end
  end

  test "--full is the one thing that parses the corpus" do
    with_bundle do |b|
      populated(b)
      path = b.bundle_path

      with_corpus_unreadable do
        assert_raises(RuntimeError) { OKF::Pro::State.call(path, today: TODAY, full: true) }
      end
    end
  end

  test "the board block carries every counter the banner and the verb print" do
    with_bundle do |b|
      populated(b)
      board = OKF::Pro::State.call(b.bundle_path, today: TODAY)["board"]

      assert_equal 1, board["in flight"]
      assert_equal 5, board["cap"]
      assert_equal 1, board["declared"]
      assert_equal 0, board["backlog"]
      assert_equal 1, board["waiting"]
      assert_equal 1, board["past chase"]
      assert_equal 2, board["inbox"]
      assert_equal 4, board["oldest"]
      assert_equal 1, board["to read"]
      assert_equal 0, board["deadlines"]
      assert_equal 0, board["conflicts open"]
    end
  end

  # A board that has lost its header has no cap to report, and reporting one
  # would be inventing the number Rule 3 exists to make visible.
  test "a board with no header reports no cap rather than a plausible one" do
    with_bundle do |b|
      path = b.bundle_path
      board = File.join(path, "board.md")
      File.write(board, OKF::Pro.read_text(board).sub(/\*\*In flight.*\n/, ""))
      state = OKF::Pro::State.call(path, today: TODAY)["board"]

      assert_nil state["cap"]
      assert_nil state["declared"]
    end
  end

  test "the last snapshot is labelled by the day it was logged under" do
    with_bundle do |b|
      populated(b)
      b.snapshot_on("2026-08-16")
      snap = OKF::Pro::State.call(b.bundle_path, today: TODAY)["last snapshot"]

      assert_equal "2026-08-16", snap["day"]
      assert_equal 1, snap["counters"]["unverified briefings"]
    end
  end

  # The log runs newest-first, and every earlier defect in `log.rb` turned on
  # that being prose rather than code. The day a reader is shown must be the
  # newest one, not the last in the file.
  test "the newest snapshot wins, not the last one in the file" do
    with_bundle do |b|
      populated(b)
      b.log_day("2026-08-16", "* **Snapshot**: inbox 9")
      b.log_day("2026-08-10", "* **Snapshot**: inbox 1")
      snap = OKF::Pro::State.call(b.bundle_path, today: TODAY)["last snapshot"]

      assert_equal "2026-08-16", snap["day"]
      assert_equal 9, snap["counters"]["inbox"]
    end
  end

  test "no snapshot at all is nil rather than a hash of zeroes" do
    with_bundle do |b|
      populated(b)

      assert_nil OKF::Pro::State.call(b.bundle_path, today: TODAY)["last snapshot"]
    end
  end

  test "today's journal is reported as open only when the file is there" do
    with_bundle do |b|
      populated(b)
      path = b.bundle_path

      refute OKF::Pro::State.call(path, today: TODAY)["log"]["journal today"]

      File.write(File.join(path, "journal", "#{TODAY}.md"), "---\ntype: Journal Entry\ntitle: x\ndescription: y\n---\n\n# x\n")

      assert OKF::Pro::State.call(path, today: TODAY)["log"]["journal today"]
    end
  end

  # Everything the payload holds must survive JSON, because `--json` is what a
  # consumer reads. A Date or a Struct in there would serialise as a string
  # nobody agreed on.
  test "the payload round-trips through JSON unchanged" do
    with_bundle do |b|
      populated(b)
      b.snapshot_on("2026-08-16")
      payload = OKF::Pro::State.call(b.bundle_path, today: TODAY, full: true)

      assert_equal payload, JSON.parse(JSON.generate(payload))
    end
  end
end
