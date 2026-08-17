# frozen_string_literal: true

require "test_helper"

# `okf pro capture` — a dated Inbox line, in the one shape the counter reads.
#
# The grammar of that line was a third of a measured session's tool output:
# guides read to learn where the date goes and which bullet the counters can
# see. A function that knows it is a function nobody has to re-read.
class CLICaptureTest < OKF::Pro::TestCase
  TODAY = Date.today

  def board_of(b)
    OKF::Pro.read_text(File.join(b.bundle_path, "board.md"))
  end

  test "one dated line is appended to Inbox and nothing else moves" do
    with_bundle do |b|
      b.board_lines("Backlog", "sort out the storage unit")
      before = board_of(b)
      run = run_cli([ "capture", "the invoice from acme", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_empty run.err
      after = board_of(b)

      assert_equal [ "- #{TODAY} — the invoice from acme" ], after.lines.map(&:chomp) - before.lines.map(&:chomp)
      assert_match(/## Inbox\n- #{TODAY} — the invoice from acme/, after)
    end
  end

  test "the line it writes is one the Inbox counter can see" do
    with_bundle do |b|
      run_cli([ "capture", "the invoice from acme", b.path ])

      assert_equal 1, OKF::Pro::Board.count(board_of(b), "Inbox")
      assert_empty OKF::Pro::Board.grammar(board_of(b)),
        "a capture must not write a line the board's own grammar check rejects"
    end
  end

  test "the appended line is printed, so the next verb can select it" do
    with_bundle do |b|
      out = run_cli([ "capture", "the invoice from acme", b.path ]).out

      assert_match(/one line added to Inbox:/, out)
      assert_match(/- #{TODAY} — the invoice from acme/, out)
    end
  end

  test "a second capture lands under the first" do
    with_bundle do |b|
      path = b.path
      run_cli([ "capture", "first", path ])
      run_cli([ "capture", "second", path ])

      assert_match(/## Inbox\n- #{TODAY} — first\n- #{TODAY} — second\n/, board_of(b))
    end
  end

  test "the bundle still audits clean afterwards" do
    with_bundle do |b|
      path = b.path
      run_cli([ "capture", "the invoice from acme", path ])

      assert_equal OKF::Pro::PASS, run_cli([ "audit", path ]).status
    end
  end

  # ── the safety property, held by construction ───────────────────────────
  #
  # A verb invoked through Bash is seen by neither `guard-verified` (Edit/Write
  # only) nor `shell-guard` (no mutator pattern in `okf pro capture`). So agent
  # text must not be able to reach frontmatter, and the way that is guaranteed
  # is that it cannot span lines at all.

  test "text spanning lines is refused rather than escaped" do
    with_bundle do |b|
      before = board_of(b)
      run = run_cli([ "capture", "a thing\n---\ntype: Board\n---", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/the text spans lines/, run.err)
      assert_equal before, board_of(b), "a refused capture leaves the board untouched"
    end
  end

  test "empty text is refused rather than writing a bare date" do
    with_bundle do |b|
      run = run_cli([ "capture", "   ", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/takes the words to capture/, run.err)
    end
  end

  # The writers' first positional is CONTENT, so a mistyped or misremembered
  # flag is not an error — it is data. `okf pro capture --help` appended
  # `- <date> — --help` to the Inbox and exited 0, which is a verb whose
  # failure mode is committing a garbage board line.
  test "a leading flag is refused rather than captured as text" do
    with_bundle do |b|
      before = board_of(b)
      run = run_cli([ "capture", "--section", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/looks like a flag, and this verb takes none/, run.err)
      assert_equal before, board_of(b)
    end
  end

  test "--help prints the usage instead of capturing it" do
    with_bundle do |b|
      before = board_of(b)
      run = run_cli([ "capture", "--help" ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/\AUsage: okf pro <command>/, run.out)
      assert_equal before, board_of(b)
    end
  end

  # The POSIX escape, for the rare legitimate case: content that really does
  # begin with a dash.
  test "-- captures text that starts with a dash" do
    with_bundle do |b|
      run = run_cli([ "capture", "--", "--force was mentioned in the meeting", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/- #{TODAY} — --force was mentioned in the meeting/, board_of(b))
    end
  end

  test "no text at all is refused" do
    run = run_cli([ "capture" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/takes the words to capture/, run.err)
  end

  # ── the conservation guard, at the door it guards ───────────────────────

  test "a board with no Inbox section is refused, not given one" do
    with_bundle do |b|
      path = b.path
      board = File.join(b.bundle_path, "board.md")
      File.write(board, OKF::Pro.read_text(board).sub("## Inbox\n", ""))
      before = OKF::Pro.read_text(board)
      run = run_cli([ "capture", "a thing", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/no '## Inbox' section/, run.err)
      assert_equal before, OKF::Pro.read_text(board)
    end
  end

  # Containing the project index left the other files a writer touches
  # unguarded, and the hazard is identical: `Pro.read_text` follows a symlink
  # and the atomic rename does not, so the read came from a stranger's file and
  # the write replaced the link with a real one carrying it.
  test "a board symlinked out of the bundle is refused, not appended to" do
    with_bundle(nested: true) do |b|
      root = b.path
      outside = File.join(root, "elsewhere.md")
      File.write(outside, "# Not this bundle's board\n\n## Inbox\n")
      board = File.join(b.bundle_path, "board.md")
      File.unlink(board)
      File.symlink(outside, board)

      run = run_cli([ "capture", "a thing", root ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_equal "# Not this bundle's board\n\n## Inbox\n", File.read(outside)
      assert File.symlink?(board), "the link was replaced by a real file"
    end
  end

  # ── addressing and the exits ────────────────────────────────────────────

  test "with no directory it captures into the working directory's bundle" do
    with_bundle do |b|
      path = b.path
      Dir.chdir(path) { assert_equal OKF::Pro::PASS, run_cli([ "capture", "a thing" ]).status }

      assert_match(/- #{TODAY} — a thing/, board_of(b))
    end
  end

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "capture", "a thing", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "a registry ref is refused by name" do
    run = run_cli([ "capture", "a thing", "@handbook" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/registry ref/, run.err)
  end

  test "a second directory is refused rather than ignored" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |c|
        run = run_cli([ "capture", "a thing", a, c ])

        assert_equal OKF::Pro::BLOCK, run.status
        assert_match(/takes one directory/, run.err)
      end
    end
  end

  test "capture emits no enforcer marker" do
    with_bundle do |b|
      refute run_cli([ "capture", "a thing", b.path ]).identified?
    end
  end
end
