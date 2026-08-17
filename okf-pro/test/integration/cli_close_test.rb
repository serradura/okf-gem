# frozen_string_literal: true

require "test_helper"

# `okf pro close` — the three mechanical moves of closure, and only those.
#
# The ritual has four moves and the first one is judgment: extract the durable
# part to `learnings/` or `glossary/`. That stays the skill's, and this verb
# reports it as owed rather than doing it — a verb that wrote a learning would
# be writing prose, and the whole reason the habit exists is that the person
# doing the work is the only one who knows what was learned.
class CLICloseTest < OKF::Pro::TestCase
  TODAY = Date.today

  # Written directly rather than through `concept`, because the fixture's
  # `write_indexes` regenerates the index of any directory holding a declared
  # concept — and this project's index is the file under test.
  def project(b, slug = "alpha", title = "Alpha migration")
    b.write("projects/#{slug}/index.md", "# #{title}\n\nOngoing.\n\n* [plan](plan.md) - the sequence.\n")
    b.write("projects/#{slug}/plan.md", <<~PLAN)
      ---
      type: Decision
      title: #{title} plan
      description: The order things move, and why that order.
      ---

      # #{title} plan

      Read endpoints first: they are idempotent, so a rollback costs nothing.
    PLAN
  end

  def index_of(b, slug = "alpha")
    OKF::Pro.read_text(File.join(b.bundle_path, "projects", slug, "index.md"))
  end

  def log_of(b)
    OKF::Pro.read_text(File.join(b.bundle_path, "log.md"))
  end

  test "the index is marked, the board lines go, and the log gains an entry" do
    with_bundle do |b|
      project(b)
      b.in_flight("[/projects/alpha/](/projects/alpha/index.md) — call the movers")
      run = run_cli([ "close", "alpha", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/\A# Alpha migration — closed #{TODAY}\n/, index_of(b))
      assert_equal 0, OKF::Pro::Board.count(OKF::Pro.read_text(File.join(b.bundle_path, "board.md")), "In flight")
      assert_match(/## #{TODAY}\n\n\* Closed \[/, log_of(b))
    end
  end

  # The marker it writes has to be one the checker accepts, or a project closed
  # by the book stays open and its board lines keep being demanded. That
  # coupling is pinned in three directions now: what the skill teaches, what
  # MARKER accepts, and what this verb emits.
  test "the marker it emits is one Pairing::MARKER accepts" do
    with_bundle do |b|
      project(b)
      run_cli([ "close", "alpha", b.path ])

      assert OKF::Pro::Pairing.marker?(index_of(b).lines.first)
      assert_includes OKF::Pro::Pairing.closed_projects(b.bundle_path), "alpha"
      refute_includes OKF::Pro::Pairing.open_projects(b.bundle_path), "alpha"
    end
  end

  test "the budget face follows the in-flight lines it removed" do
    with_bundle do |b|
      project(b)
      project(b, "beta", "Beta")
      b.in_flight("[/projects/alpha/](/projects/alpha/index.md) — one",
        "[/projects/beta/](/projects/beta/index.md) — two")
      run_cli([ "close", "alpha", b.path ])
      board = OKF::Pro.read_text(File.join(b.bundle_path, "board.md"))

      assert_equal 1, OKF::Pro::Board.budget(board).declared
      assert_empty OKF::Pro::Budget.check_text(board)
    end
  end

  test "board lines in any section are removed, not only in-flight ones" do
    with_bundle do |b|
      project(b)
      b.board_lines("Backlog", "[/projects/alpha/](/projects/alpha/index.md) — later")
      b.board_lines("To read", "[/projects/alpha/plan.md] — the plan")
      run = run_cli([ "close", "alpha", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      board = OKF::Pro.read_text(File.join(b.bundle_path, "board.md"))

      refute_match(%r{/projects/alpha}, OKF::Pro::Board.visible(board))
      assert_match(/2 board line\(s\) removed/, run.out)
    end
  end

  test "the durable extraction is reported as owed, never done" do
    with_bundle do |b|
      project(b)
      out = run_cli([ "close", "alpha", b.path ]).out

      assert_match(/the durable part of this work belongs in learnings\/ or glossary\//, out)
      assert_empty Dir.glob(File.join(b.bundle_path, "learnings", "*.md")).reject { |f| File.basename(f) == "index.md" }
    end
  end

  # Writing a log entry gives the day a heading, and from that moment the audit
  # the pre-commit door runs asks that day for its Snapshot line. A verb that
  # quietly turned the next commit into a refusal without naming the fix would
  # be teaching its user that the gates are arbitrary.
  test "the obligation the log entry creates is named" do
    with_bundle do |b|
      project(b)
      out = run_cli([ "close", "alpha", b.path ]).out

      assert_match(/owes its Snapshot line/, out)
      assert_match(/`okf pro snapshot` computes it/, out)
    end
  end

  test "a day that already carries its snapshot is not told it owes one" do
    with_bundle do |b|
      project(b)
      b.snapshot_on(TODAY.to_s)

      refute_match(/owes its Snapshot line/, run_cli([ "close", "alpha", b.path ]).out)
    end
  end

  # ── idempotence ─────────────────────────────────────────────────────────

  test "closing twice does nothing the second time and says so" do
    with_bundle do |b|
      project(b)
      path = b.path
      run_cli([ "close", "alpha", path ])
      index = index_of(b)
      log = log_of(b)
      run = run_cli([ "close", "alpha", path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/already closed and carries no board line/, run.out)
      assert_equal index, index_of(b)
      assert_equal log, log_of(b)
    end
  end

  test "a closed project that still carries a board line finishes the job" do
    with_bundle do |b|
      project(b)
      b.board_lines("Backlog", "[/projects/alpha/](/projects/alpha/index.md) — a leftover")
      path = b.path
      File.write(File.join(b.bundle_path, "projects", "alpha", "index.md"),
        "# Alpha migration — closed #{TODAY}\n\nDone.\n\n* [plan](plan.md) - the sequence.\n")
      run = run_cli([ "close", "alpha", path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/already carried the closure marker/, run.out)
      assert_match(/1 board line\(s\) removed/, run.out)
      assert_equal 1, index_of(b).scan(/closed/i).size, "the marker must not be doubled"
    end
  end

  # ── containment ─────────────────────────────────────────────────────────

  # `Pairing.closed?` reads this index through `Pro.read_contained` and
  # answers "open" when the link leaves the bundle, so a writer that marked
  # it anyway rewrote a stranger's file, reported success, and left the audit
  # still demanding the closure it had just claimed to write. Running it
  # twice appended a second marker, so it was unbounded as well as wrong.
  test "a project directory symlinked out of the bundle is refused, not marked" do
    with_bundle(nested: true) do |b|
      root = b.path
      outside = File.join(root, "elsewhere")
      FileUtils.mkdir_p(outside)
      stranger = File.join(outside, "index.md")
      File.write(stranger, "# Someone elses doc\n\nNot this bundle's.\n")
      FileUtils.mkdir_p(File.join(b.bundle_path, "projects"))
      File.symlink(outside, File.join(b.bundle_path, "projects", "escapee"))

      run = run_cli([ "close", "escapee", root ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_equal "# Someone elses doc\n\nNot this bundle's.\n", File.read(stranger)
      assert_match(/escapee/, run.err)
    end
  end

  # The board line is the demand, and the refusal above is what keeps it
  # visible: a project the checker reads as open keeps being asked about.
  test "the board line survives a refused escape, so the demand stays visible" do
    with_bundle(nested: true) do |b|
      b.in_flight("[/projects/escapee/](/projects/escapee/index.md) — call the movers")
      root = b.path
      outside = File.join(root, "elsewhere")
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, "index.md"), "# Someone elses doc\n\nNot this bundle's.\n")
      FileUtils.mkdir_p(File.join(b.bundle_path, "projects"))
      File.symlink(outside, File.join(b.bundle_path, "projects", "escapee"))
      run_cli([ "close", "escapee", root ])
      board = OKF::Pro.read_text(File.join(b.bundle_path, "board.md"))

      assert_equal 1, OKF::Pro::Board.count(board, "In flight")
    end
  end

  # The directory can be contained while the file inside it is not.
  # `Pro.read_text` follows a symlink and `File.rename` does not, so a
  # `projects/<slug>/index.md` pointing out of the bundle had a stranger's
  # title read, marked, and materialised as a real file inside the bundle —
  # while `Pairing.closed?` refused to read that same path and answered
  # "open". Containing the directory is not containing the file.
  test "a project index symlinked out of the bundle is refused, not marked" do
    with_bundle(nested: true) do |b|
      root = b.path
      outside = File.join(root, "elsewhere")
      FileUtils.mkdir_p(outside)
      stranger = File.join(outside, "index.md")
      File.write(stranger, "# Someone elses doc\n\nNot this bundle's.\n")
      FileUtils.mkdir_p(File.join(b.bundle_path, "projects", "alpha"))
      File.symlink(stranger, File.join(b.bundle_path, "projects", "alpha", "index.md"))

      run = run_cli([ "close", "alpha", root ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_equal "# Someone elses doc\n\nNot this bundle's.\n",
        OKF::Pro.read_text(File.join(b.bundle_path, "projects", "alpha", "index.md"))
    end
  end

  # ── the selector and the exits ──────────────────────────────────────────

  # The message the writers share offers a substring and a `/projects/<slug>`
  # link, and this verb takes neither: a project is one directory segment, so
  # `/projects/alpha/index.md` — the exact link a board line carries, and what
  # `okf pro board` prints — is a refusal. A message naming what the verb
  # rejects sends the reader to try it.
  test "the missing-argument message names what this verb actually takes" do
    run = run_cli([ "close" ])

    assert_equal OKF::Pro::BLOCK, run.status
    refute_match(/substring only one board line carries/, run.err)
    assert_match(/one directory segment/, run.err)
  end

  # The link a board line carries, verbatim. `okf pro board` prints it and
  # `Board::Edit.by_target` treats it as the same commitment as the bare slug,
  # so refusing it here made the one string an agent has to hand the wrong one.
  test "the index link a board line carries names the same project as its slug" do
    with_bundle do |b|
      project(b)
      b.in_flight("[/projects/alpha/](/projects/alpha/index.md) — call the movers")
      run = run_cli([ "close", "/projects/alpha/index.md", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/\A# Alpha migration — closed #{TODAY}\n/, index_of(b))
    end
  end

  test "a project path names the same project as its slug" do
    with_bundle do |b|
      project(b)

      assert_equal OKF::Pro::PASS, run_cli([ "close", "projects/alpha", b.path ]).status
    end
  end

  test "a project that does not exist is exit 2 and points at the listing verb" do
    with_bundle do |b|
      run = run_cli([ "close", "nothing", b.path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(%r{projects/nothing/ does not exist}, run.err)
      assert_match(/`okf pro state` lists the open projects/, run.err)
    end
  end

  test "a project directory with no index is exit 2, because closure is a marker on one" do
    with_bundle do |b|
      path = b.path
      FileUtils.mkdir_p(File.join(b.bundle_path, "projects", "bare"))
      run = run_cli([ "close", "bare", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/index\.md does not exist/, run.err)
    end
  end

  # A first line the marker cannot be appended to is refused rather than
  # marked: a project the checker still reads as open, with a sentence about
  # closure in it, is the worst of both.
  test "a first line that is not a heading is refused" do
    with_bundle do |b|
      path = b.path
      FileUtils.mkdir_p(File.join(b.bundle_path, "projects", "odd"))
      File.write(File.join(b.bundle_path, "projects", "odd", "index.md"), "not closed yet\n\nBody.\n")
      run = run_cli([ "close", "odd", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/does not open with a heading/, run.err)
      assert_equal "not closed yet\n\nBody.\n", OKF::Pro.read_text(File.join(b.bundle_path, "projects", "odd", "index.md"))
    end
  end

  # The reason the check is the SHAPE of the line rather than merely whether
  # the result satisfies `Pairing::MARKER`. An index carrying YAML frontmatter
  # opens with `---`, and `Pairing.marker?("--- — closed <date>")` is TRUE —
  # the regex needs only the word and a date. So a satisfied-marker check
  # passed, the fence was destroyed, and the concept silently lost its `type`,
  # `title` and `description` while `okf validate` still exited 0. `Conserve`
  # cannot see it either: the mangling was the declared edit.
  test "an index opening with a frontmatter fence is refused, not mangled" do
    with_bundle do |b|
      path = b.path
      index = File.join(b.bundle_path, "projects", "fenced", "index.md")
      FileUtils.mkdir_p(File.dirname(index))
      body = "---\ntype: Overview\ntitle: Fenced\ndescription: A project index somebody gave frontmatter.\n---\n\n# Fenced\n"
      File.write(index, body)

      assert OKF::Pro::Pairing.marker?("--- — closed #{TODAY}"),
        "if MARKER stopped accepting this, the shape check below is guarding a hole that closed"

      run = run_cli([ "close", "fenced", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/frontmatter/, run.err)
      assert_equal body, OKF::Pro.read_text(index)
    end
  end

  # The belt to the heading check's braces, and it is reachable: a title that
  # NEGATES the word leaves `Pairing::MARKER` refusing the result even though
  # the line is a perfectly good heading. Marking it would produce a project
  # the checker still reads as open, with a sentence about closure in it.
  test "a heading whose marker the checker would refuse is refused" do
    with_bundle do |b|
      path = b.path
      index = File.join(b.bundle_path, "projects", "denied", "index.md")
      FileUtils.mkdir_p(File.dirname(index))
      File.write(index, "# The thing that was not closed\n\nBody.\n")
      run = run_cli([ "close", "denied", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/would not produce a closure marker the checker accepts/, run.err)
      assert_match(/\A# The thing that was not closed\n/, OKF::Pro.read_text(index))
    end
  end

  # Three files change and the set is not atomic, so the ordering is the
  # safety: every check runs before anything lands. Checking as it went left a
  # real half-closed bundle — the index marked, the board line surviving, no
  # log entry, and a message saying nothing had happened.
  test "a refusal from a later move leaves the earlier ones unwritten" do
    with_bundle do |b|
      project(b)
      b.in_flight("[/projects/alpha/](/projects/alpha/index.md) — one")
      path = b.path
      board = File.join(b.bundle_path, "board.md")
      File.write(board, OKF::Pro.read_text(board).sub(/\*\*In flight.*\n/, ""))
      board_before = OKF::Pro.read_text(board)
      index_before = index_of(b)
      log_before = log_of(b)
      run = run_cli([ "close", "alpha", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/lost its 'In flight: k\/CAP' header/, run.err)
      assert_equal index_before, index_of(b), "the marker landed before a later move refused"
      assert_equal board_before, OKF::Pro.read_text(board)
      assert_equal log_before, log_of(b)
    end
  end

  # `File.join` resolves `..` happily, and this verb marks a file's first line.
  # A slug that can leave `projects/` would put a closure marker on a
  # stranger's index — so it is refused rather than normalised: quietly
  # rewriting a path the caller gave is how a traversal becomes an edit nobody
  # sees.
  test "a slug that could leave projects/ is refused rather than normalised" do
    with_bundle do |b|
      project(b)
      path = b.path
      outside = File.join(b.bundle_path, "areas", "corpus.md")
      before = OKF::Pro.read_text(outside)

      [ "../areas", "../../etc", "..", ".", "alpha/../../areas", "a/b" ].each do |bad|
        run = run_cli([ "close", bad, path ])

        assert_equal OKF::Pro::BLOCK, run.status, "#{bad} was not refused"
        assert_match(/is not a project name/, run.err)
      end

      assert_equal before, OKF::Pro.read_text(outside)
    end
  end

  test "no project at all is refused" do
    run = run_cli([ "close" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/takes the project to close/, run.err)
  end

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "close", "alpha", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "a registry ref is refused by name" do
    run = run_cli([ "close", "alpha", "@handbook" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/registry ref/, run.err)
  end

  test "a second directory is refused rather than ignored" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |c|
        run = run_cli([ "close", "alpha", a, c ])

        assert_equal OKF::Pro::BLOCK, run.status
        assert_match(/takes one directory/, run.err)
      end
    end
  end
end
