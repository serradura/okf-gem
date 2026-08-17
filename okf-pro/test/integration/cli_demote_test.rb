# frozen_string_literal: true

require "test_helper"

# `okf pro demote` — In flight back to Backlog.
#
# The half of Rule 3 that makes the cap survivable: promotion requires
# demotion, so the demotion has to be as cheap as the promotion or the cap
# gets renegotiated by attrition instead of by decision.
class CLIDemoteTest < OKF::Pro::TestCase
  def board_of(b)
    OKF::Pro.read_text(File.join(b.bundle_path, "board.md"))
  end

  def in_flight(b, *lines)
    b.write("projects/alpha/index.md", "# Alpha\n\nOpen.\n")
    b.in_flight(*lines)
  end

  test "an in-flight line moves to Backlog and the header follows it" do
    with_bundle do |b|
      in_flight(b, "[/projects/alpha/](/projects/alpha/index.md) — call the movers",
        "[/projects/alpha/index.md](/projects/alpha/index.md) — second")
      run = run_cli([ "demote", "call the movers", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      board = board_of(b)

      assert_equal 1, OKF::Pro::Board.count(board, "In flight")
      assert_equal 1, OKF::Pro::Board.count(board, "Backlog")
      assert_equal 1, OKF::Pro::Board.budget(board).declared
      assert_empty OKF::Pro::Budget.check_text(board)
    end
  end

  test "the line and the new header are reported" do
    with_bundle do |b|
      in_flight(b, "[/projects/alpha/](/projects/alpha/index.md) — call the movers")
      out = run_cli([ "demote", "alpha", b.path ]).out

      assert_match(/moved from In flight to Backlog:/, out)
      assert_match(/header now reads \*\*In flight: 0\/5\*\*/, out)
    end
  end

  # The owed-work note belongs to promotion. Demoting owes nobody a next
  # action, and a verb that printed one either way would be printing wallpaper.
  test "demotion carries no owed-work note" do
    with_bundle do |b|
      in_flight(b, "[/projects/alpha/](/projects/alpha/index.md) — call the movers")

      refute_match(/next-action line/, run_cli([ "demote", "alpha", b.path ]).out)
    end
  end

  test "demoting frees a slot the cap check then allows" do
    with_bundle do |b|
      in_flight(b, "[/projects/alpha/](/projects/alpha/index.md) — one")
      b.board_lines("Backlog", "[/projects/beta/](/projects/beta/index.md) — two")
      b.write("projects/beta/index.md", "# Beta\n\nOpen.\n")
      b.budget(cap: 1)
      path = b.path

      assert_equal OKF::Pro::BLOCK, run_cli([ "promote", "beta", path ]).status
      assert_equal OKF::Pro::PASS, run_cli([ "demote", "alpha", path ]).status
      assert_equal OKF::Pro::PASS, run_cli([ "promote", "beta", path ]).status
    end
  end

  # ── selectors ───────────────────────────────────────────────────────────
  #
  # Scoped to In flight, so a Backlog line with a similar name cannot be the
  # thing that moves.

  test "only in-flight lines are in scope" do
    with_bundle do |b|
      in_flight(b, "[/projects/alpha/](/projects/alpha/index.md) — one")
      b.board_lines("Backlog", "a backlogged thing")
      run = run_cli([ "demote", "backlogged", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/no board line under In flight matches/, run.err)
    end
  end

  test "an ambiguous selector refuses and the board is untouched" do
    with_bundle do |b|
      in_flight(b, "the invoice from acme", "the invoice from beta")
      b.budget(declared: 2)
      before = board_of(b)
      run = run_cli([ "demote", "the invoice", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/matches 2 board lines/, run.err)
      assert_equal before, board_of(b)
    end
  end

  test "no selector at all is refused" do
    run = run_cli([ "demote" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/takes what to act on/, run.err)
  end

  # Every verb that rewrites the board asks the same question, and each asks it
  # for itself: a guard on one verb's path is not a guard on another's.
  test "a board symlinked out of the bundle is refused" do
    with_bundle(nested: true) do |b|
      b.in_flight("a thing")
      root = b.path
      outside = File.join(root, "elsewhere.md")
      FileUtils.cp(File.join(b.bundle_path, "board.md"), outside)
      board = File.join(b.bundle_path, "board.md")
      File.unlink(board)
      File.symlink(outside, board)

      run = run_cli([ "demote", "a thing", root ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert File.symlink?(board), "the link was replaced by a real file"
      assert_match(/resolves outside/, run.err)
    end
  end

  # ── the exits ───────────────────────────────────────────────────────────

  test "a board with no budget header is refused rather than given a cap" do
    with_bundle do |b|
      in_flight(b, "[/projects/alpha/](/projects/alpha/index.md) — one")
      path = b.path
      board = File.join(b.bundle_path, "board.md")
      File.write(board, OKF::Pro.read_text(board).sub(/\*\*In flight.*\n/, ""))
      run = run_cli([ "demote", "alpha", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/lost its 'In flight: k\/CAP' header/, run.err)
    end
  end

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "demote", "alpha", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "a registry ref is refused by name" do
    run = run_cli([ "demote", "alpha", "@handbook" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/registry ref/, run.err)
  end

  test "a second directory is refused rather than ignored" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |c|
        run = run_cli([ "demote", "alpha", a, c ])

        assert_equal OKF::Pro::BLOCK, run.status
        assert_match(/takes one directory/, run.err)
      end
    end
  end
end
