# frozen_string_literal: true

require "test_helper"

# `okf pro promote` — Inbox or Backlog to In flight, and the budget face kept
# truthful in the same write.
#
# Two things it must never do, and both are pinned here: exceed the cap (Rule 3
# is the one refusal that makes overload undeniable on the day it happens), and
# guess which commitment was meant when a selector matches more than one.
class CLIPromoteTest < OKF::Pro::TestCase
  TODAY = Date.today

  def board_of(b)
    OKF::Pro.read_text(File.join(b.bundle_path, "board.md"))
  end

  def with_backlog(b, *lines)
    b.write("projects/alpha/index.md", "# Alpha\n\nOpen.\n")
    b.board_lines("Backlog", *lines)
  end

  test "a backlog line moves to In flight and the header follows it" do
    with_bundle do |b|
      with_backlog(b, "[/projects/alpha/](/projects/alpha/index.md) — call the movers")
      run = run_cli([ "promote", "alpha", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      board = board_of(b)

      assert_equal 1, OKF::Pro::Board.count(board, "In flight")
      assert_equal 0, OKF::Pro::Board.count(board, "Backlog")
      assert_equal 1, OKF::Pro::Board.budget(board).declared
      assert_empty OKF::Pro::Budget.check_text(board), "the budget face must not be left lying"
    end
  end

  test "an inbox line is promotable too, and keeps its dated text verbatim" do
    with_bundle do |b|
      b.inbox("#{TODAY} — the invoice from acme")
      run_cli([ "promote", "invoice", b.path ])

      assert_match(/## In flight\n- #{TODAY} — the invoice from acme\n/, board_of(b))
    end
  end

  test "the line and the new header are both reported" do
    with_bundle do |b|
      with_backlog(b, "[/projects/alpha/](/projects/alpha/index.md) — call the movers")
      out = run_cli([ "promote", "alpha", b.path ]).out

      assert_match(/moved from Backlog to In flight:/, out)
      assert_match(/header now reads \*\*In flight: 1\/5\*\*/, out)
    end
  end

  # The judgment half is said out loud rather than done. A verb that wrote the
  # journal line would be writing prose, and prose is the skill's.
  test "the promotion names what it did not do" do
    with_bundle do |b|
      with_backlog(b, "[/projects/alpha/](/projects/alpha/index.md) — call the movers")
      out = run_cli([ "promote", "alpha", b.path ]).out

      assert_match(/a next-action line and a journal entry linking it/, out)
    end
  end

  # ── Rule 3 ──────────────────────────────────────────────────────────────

  test "promoting past the cap is refused and the board is untouched" do
    with_bundle do |b|
      b.in_flight("one", "two").budget(cap: 2)
      with_backlog(b, "[/projects/alpha/](/projects/alpha/index.md) — a third")
      before = board_of(b)
      run = run_cli([ "promote", "alpha", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/RULE 3: 2 in flight against a cap of 2/, run.err)
      assert_match(/Promotion requires demotion/, run.err)
      assert_equal before, board_of(b)
    end
  end

  test "promoting to exactly the cap is allowed" do
    with_bundle do |b|
      b.in_flight("one").budget(cap: 2)
      with_backlog(b, "[/projects/alpha/](/projects/alpha/index.md) — a second")

      assert_equal OKF::Pro::PASS, run_cli([ "promote", "alpha", b.path ]).status
      assert_equal 2, OKF::Pro::Board.count(board_of(b), "In flight")
    end
  end

  # A board with no header has no cap, and inventing one is how a budget stops
  # meaning anything.
  test "a board with no budget header is refused rather than given a cap" do
    with_bundle do |b|
      with_backlog(b, "[/projects/alpha/](/projects/alpha/index.md) — a thing")
      path = b.path
      board = File.join(b.bundle_path, "board.md")
      File.write(board, OKF::Pro.read_text(board).sub(/\*\*In flight.*\n/, ""))
      before = OKF::Pro.read_text(board)
      run = run_cli([ "promote", "alpha", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/lost its 'In flight: k\/CAP' header/, run.err)
      assert_equal before, OKF::Pro.read_text(board)
    end
  end

  # ── selectors ───────────────────────────────────────────────────────────

  test "an ambiguous selector refuses and lists every match" do
    with_bundle do |b|
      with_backlog(b, "the invoice from acme", "the invoice from beta")
      before = board_of(b)
      run = run_cli([ "promote", "the invoice", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/matches 2 board lines/, run.err)
      assert_match(/from acme/, run.err)
      assert_match(/from beta/, run.err)
      assert_equal before, board_of(b)
    end
  end

  test "a selector matching nothing refuses and points at the listing verb" do
    with_bundle do |b|
      with_backlog(b, "a thing")
      run = run_cli([ "promote", "nothing like it", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/no board line under Inbox or Backlog matches/, run.err)
      assert_match(/`okf pro board` lists what is there/, run.err)
    end
  end

  # In flight is where this verb moves things TO, so a line already there is
  # out of scope — and saying "no match" is the honest answer rather than
  # moving it to where it already is.
  test "a line already in flight is not promotable" do
    with_bundle do |b|
      b.in_flight("[/projects/alpha/](/projects/alpha/index.md) — already going")
      b.write("projects/alpha/index.md", "# Alpha\n\nOpen.\n")
      run = run_cli([ "promote", "alpha", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/no board line under Inbox or Backlog/, run.err)
    end
  end

  test "a leading flag is refused rather than read as a selector" do
    with_bundle do |b|
      with_backlog(b, "a thing")
      run = run_cli([ "promote", "--json", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/looks like a flag, and this verb takes none/, run.err)
    end
  end

  test "no selector at all is refused" do
    run = run_cli([ "promote" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/takes what to act on/, run.err)
  end

  # `okf pro board` lists a line without its trailing comment, and the move
  # walks the raw text — so the two disagree about a commented line. Refusing
  # is correct (moving the visible half would drop the comment, which is the
  # whole thing `Conserve` exists to prevent), but the message has to send the
  # reader to the right place.
  test "a line carrying a trailing comment is refused with the reason" do
    with_bundle do |b|
      with_backlog(b, "call the movers <!-- quoted 2026-08-01 -->")
      before = board_of(b)
      run = run_cli([ "promote", "call the movers", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/trailing/, run.err)
      assert_match(/take the comment off the line first/, run.err)
      assert_equal before, board_of(b)
    end
  end

  # A bundle can resolve with no board at all — an index beside `log.md` is
  # enough — and "could not run (Errno::ENOENT)" is a true answer to the wrong
  # question.
  test "a bundle with no board says so rather than reporting a file error" do
    with_bundle do |b|
      path = b.path
      File.delete(File.join(b.bundle_path, "board.md"))
      run = run_cli([ "promote", "alpha", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/has no board\.md to edit/, run.err)
      refute_match(/Errno/, run.err)
    end
  end

  # The end-to-end shape of the substring splice: the verb refused, named the
  # prose line rather than the header, and stayed refused until somebody
  # edited prose that was never the problem.
  test "a prose line quoting the header is not what the header edit lands on" do
    with_bundle do |b|
      b.in_flight("already")
      b.board_lines("Backlog", "[/projects/alpha/](/projects/alpha/index.md) — a thing")
      path = b.path
      board_path = File.join(b.bundle_path, "board.md")
      File.write(board_path, OKF::Pro.read_text(board_path)
        .sub("# Board\n", "# Board\n\nSee **In flight: 1/5** · updated fixture\n"))

      run = run_cli([ "promote", "alpha", path ])
      after = OKF::Pro.read_text(board_path)

      assert_equal OKF::Pro::PASS, run.status
      assert_includes after, "See **In flight: 1/5** · updated fixture"
      assert_equal 2, OKF::Pro::Board.budget(after).declared
    end
  end

  # Every verb that rewrites the board asks the same question, and each asks it
  # for itself: a guard on one verb's path is not a guard on another's.
  test "a board symlinked out of the bundle is refused" do
    with_bundle(nested: true) do |b|
      b.board_lines("Backlog", "- a thing")
      root = b.path
      outside = File.join(root, "elsewhere.md")
      FileUtils.cp(File.join(b.bundle_path, "board.md"), outside)
      board = File.join(b.bundle_path, "board.md")
      File.unlink(board)
      File.symlink(outside, board)

      run = run_cli([ "promote", "a thing", root ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert File.symlink?(board), "the link was replaced by a real file"
      assert_match(/resolves outside/, run.err)
    end
  end

  # ── addressing and the exits ────────────────────────────────────────────

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "promote", "alpha", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "a registry ref is refused by name" do
    run = run_cli([ "promote", "alpha", "@handbook" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/registry ref/, run.err)
  end

  test "a second directory is refused rather than ignored" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |c|
        run = run_cli([ "promote", "alpha", a, c ])

        assert_equal OKF::Pro::BLOCK, run.status
        assert_match(/takes one directory/, run.err)
      end
    end
  end
end
