# frozen_string_literal: true

require "test_helper"

# The commit-time door is a shell script, so it is tested as one: a real git
# repository, a real index, and the checker reached the same way production
# reaches it — `okf` on PATH, resolved by the hook itself.
#
# There is deliberately no environment seam. An env var honoured by the
# production hook is a one-export bypass (`OKF_PRO_BIN=/usr/bin/true` and
# every commit "passes"), so the fixture puts a real okf on PATH instead of
# teaching the hook a second way to be told where the checker is.
#
# What is pinned: the STAGED tree is what gets audited. A worktree audit passed
# a broken commit whose worktree had been quietly fixed, and refused a clean
# commit sitting next to unrelated dirty files — wrong in both directions, each
# in the direction the hook's own header forbids.
class PrecommitTest < OKF::Pro::TestCase
  HOOK = File.expand_path("../../lib/okf/pro/template/gem/.githooks/pre-commit", __dir__)

  def run_hook(dir, env)
    system(env, HOOK, chdir: dir, out: File::NULL, err: File::NULL)
    $?.exitstatus
  end

  def stage_all(dir)
    system("git", "-C", dir, "add", "-A", out: File::NULL, err: File::NULL)
  end

  # `.claude/hooks/run` proves identity with the MARKER handshake and says why
  # in its own header: a stray `okf` on PATH that exits 0 is indistinguishable
  # from a clean gate by status alone. This door only asked `command -v okf` and
  # then trusted the exit status, so a shim turned both gates off in silence —
  # the contract's third clause broken at the one door that exists for the edit
  # the other two never see.
  def test_a_stray_okf_on_path_is_refused_rather_than_trusted
    with_bundle(git: true, nested: true) do |b|
      dir = b.path
      stage_all(dir)

      with_okf_on_path("#!/bin/sh\nexit 0\n") do |env|
        refute_equal 0, run_hook(dir, env),
          "a shim that exits 0 turned both gates off and the commit went through"
      end
    end
  end

  def test_a_broken_staged_tree_is_refused_even_when_the_worktree_was_fixed
    with_bundle(git: true, nested: true) do |b|
      dir = b.path
      board = File.join(b.dir, "board.md")
      good = OKF::Pro.read_text(board)

      File.write(board, good + "- [/reference/ghost.md] — a link to nothing\n")
      stage_all(dir)
      File.write(board, good) # worktree fixed; the index still holds the break

      with_okf_on_path do |env|
        refute_equal 0, run_hook(dir, env),
          "the staged tree is broken; auditing the worktree would have passed it"
      end
    end
  end

  def test_a_clean_staged_tree_passes_despite_a_broken_worktree
    with_bundle(git: true, nested: true) do |b|
      dir = b.path
      stage_all(dir)
      board = File.join(b.dir, "board.md")
      File.write(board, OKF::Pro.read_text(board) + "- [/reference/ghost.md] — unstaged breakage\n")

      with_okf_on_path do |env|
        assert_equal 0, run_hook(dir, env),
          "the staged tree is clean; the unstaged breakage is not this commit's"
      end
    end
  end

  # The same contract the agent-time door keeps, at the commit door: a gate that
  # cannot find its checker refuses rather than waving the commit through. Git
  # reads any non-zero status as a refusal here, so this one does not need the
  # hook protocol's 2 — but it does need to not be 0.
  def test_a_missing_checker_refuses_the_commit
    with_bundle(git: true, nested: true) do |b|
      dir = b.path
      stage_all(dir)

      Dir.mktmpdir("no-okf-") do |empty|
        path = "#{empty}:/usr/bin:/bin"
        skip "an okf is installed under /usr/bin or /bin on this host" if system({ "PATH" => path },
          "command -v okf > /dev/null 2>&1")

        refute_equal 0, run_hook(dir, cleared_bundler_env.merge("PATH" => path))
      end
    end
  end

  # The append-only record is a question about the CHANGE, and it runs first:
  # materialise the staged tree and the modification is no longer visible as
  # one, so an audit of that tree cannot see it at all. A rewritten past day is
  # not a lint finding — it is the artefact gone.
  def test_rewriting_a_past_journal_day_refuses_the_commit
    with_bundle(git: true, nested: true) do |b|
      b.write("journal/2020-01-01.md", "# 2020-01-01\n\nA day already recorded.\n")
      dir = b.path
      stage_all(dir)
      system("git", "-C", dir, "-c", "user.email=t@e.st", "-c", "user.name=T",
        "commit", "-qm", "day one", out: File::NULL, err: File::NULL)

      File.write(File.join(b.dir, "journal", "2020-01-01.md"), "# 2020-01-01\n\nRewritten.\n")
      stage_all(dir)

      with_okf_on_path do |env|
        refute_equal 0, run_hook(dir, env),
          "records are append-only; a rewritten past day must not commit"
      end
    end
  end
end
