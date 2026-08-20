# frozen_string_literal: true

require "test_helper"

# `okf pro board` — one row per line, with what a reader would otherwise
# re-derive by counting headings in a `cat`: which section it sits under, the
# two date shapes the counters read, its age, and its bundle links.
#
# It is also what makes the selectors usable: `promote` and `demote` refuse on
# ambiguity, and this is where you look to find the substring only one line
# carries.
class CLIBoardTest < OKF::Pro::TestCase
  TODAY = Date.today

  def populated(b)
    b.write("projects/home-move/index.md", "# Home move\n\nOngoing.\n")
    b.in_flight("[/projects/home-move/](/projects/home-move/index.md) — call the movers")
    b.inbox("#{TODAY - 4} — the invoice from acme")
    b.board_lines("Backlog", "sort out the storage unit")
    b.board_lines("Waiting", "Landlord: inspection — chase #{TODAY - 3}")
  end

  test "every visible line is a row, tagged with its section" do
    with_bundle do |b|
      populated(b)
      run = run_cli([ "board", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_empty run.err
      assert_match(/^\[In flight\] .*call the movers$/, run.out)
      assert_match(/^\[Backlog\] - sort out the storage unit$/, run.out)
    end
  end

  test "a dated line carries its age and a waiting line its chase date" do
    with_bundle do |b|
      populated(b)
      out = run_cli([ "board", b.path ]).out

      assert_match(/^\[Inbox\] \(4d\) - #{TODAY - 4} — the invoice from acme$/, out)
      assert_match(/^\[Waiting\] \[chase #{TODAY - 3}\] - Landlord/, out)
    end
  end

  test "an empty board says so rather than printing nothing" do
    with_bundle do |b|
      run = run_cli([ "board", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/no lines/, run.out)
    end
  end

  # A commented-out sample line is not board content — the counters cannot see
  # it, and a listing that showed it would offer a selector nothing can match.
  test "a commented line is not a row" do
    with_bundle do |b|
      populated(b)
      path = b.path
      board = File.join(b.bundle_path, "board.md")
      File.write(board, OKF::Pro.read_text(board).sub("## Backlog\n", "## Backlog\n<!-- - a sample line -->\n"))

      refute_match(/a sample line/, run_cli([ "board", path ]).out)
    end
  end

  # ── --section ───────────────────────────────────────────────────────────

  test "--section narrows the listing to one section" do
    with_bundle do |b|
      populated(b)
      out = run_cli([ "board", b.path, "--section", "Backlog" ]).out

      assert_match(/storage unit/, out)
      refute_match(/call the movers/, out)
    end
  end

  test "--section is matched without regard to case" do
    with_bundle do |b|
      populated(b)

      assert_match(/storage unit/, run_cli([ "board", b.path, "--section", "backlog" ]).out)
    end
  end

  # An empty section and a misspelled one look identical in the output and mean
  # opposite things. That is the quiet-zero class this whole module exists to
  # refuse, so the heading is asked for by name.
  test "a section the board does not have is exit 2, not an empty answer" do
    with_bundle do |b|
      populated(b)
      run = run_cli([ "board", b.path, "--section", "Someday" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/no '## Someday' section/, run.err)
      assert_match(/indistinguishable from a section that is simply empty/, run.err)
    end
  end

  test "a section that exists and is empty answers with no rows and exit 0" do
    with_bundle do |b|
      populated(b)
      run = run_cli([ "board", b.path, "--section", "To read" ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/no lines/, run.out)
    end
  end

  test "--section with no value is a usage error" do
    with_bundle do |b|
      run = run_cli([ "board", b.path, "--section" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/missing argument/, run.err)
    end
  end

  # ── --json ──────────────────────────────────────────────────────────────

  test "--json emits one object per line with its dates and targets" do
    with_bundle do |b|
      populated(b)
      rows = JSON.parse(run_cli([ "board", b.path, "--json" ]).out)

      in_flight = rows.find { |row| row["section"] == "In flight" }

      assert_equal [ "/projects/home-move/index.md" ], in_flight["targets"]
      assert_nil in_flight["date"]

      inbox = rows.find { |row| row["section"] == "Inbox" }

      assert_equal (TODAY - 4).to_s, inbox["date"]
      assert_equal 4, inbox["age"]

      waiting = rows.find { |row| row["section"] == "Waiting" }

      assert_equal (TODAY - 3).to_s, waiting["chase"]
    end
  end

  test "--pretty is --json, indented" do
    with_bundle do |b|
      populated(b)
      run = run_cli([ "board", b.path, "--pretty" ])

      assert_match(/\A\[\n  \{/, run.out)
      assert_kind_of Array, JSON.parse(run.out)
    end
  end

  test "--json --section narrows the same rows" do
    with_bundle do |b|
      populated(b)
      rows = JSON.parse(run_cli([ "board", b.path, "--json", "--section", "Inbox" ]).out)

      assert_equal 1, rows.size
      assert_equal "Inbox", rows.first["section"]
    end
  end

  # ── the exits ───────────────────────────────────────────────────────────

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "board", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "a bundle with no board is exit 2" do
    with_bundle do |b|
      path = b.path
      File.delete(File.join(b.bundle_path, "board.md"))
      run = run_cli([ "board", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/has no board\.md to read/, run.err)
    end
  end

  test "an unknown flag is a usage error" do
    with_bundle do |b|
      run = run_cli([ "board", b.path, "--full" ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/invalid option: --full/, run.err)
    end
  end
end
