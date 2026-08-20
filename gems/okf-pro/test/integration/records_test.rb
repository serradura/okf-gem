# frozen_string_literal: true

require "test_helper"

# The append-only record, asked of git instead of a tool event. journal_guard
# refuses a past-day edit at the agent's tool boundary — the right place to
# catch it and the wrong place to rely on, since it only sees Edit and Write.
# A shell redirect, an editor, or a patch produces no event at all, and the
# record they rewrite is the one artefact nobody can reconstruct.
class RecordsTest < OKF::Pro::TestCase
  TODAY = Date.new(2026, 8, 12)

  def git(dir, *args)
    system("git", "-C", dir, *args, out: File::NULL, err: File::NULL)
  end

  def commit_all(dir)
    git(dir, "add", "-A")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "fixture")
  end

  # A committed bundle with one past journal day already in HEAD.
  def with_history
    with_bundle(git: true) do |b|
      b.write("journal/2026-01-01.md",
        "---\ntype: Journal Entry\ntitle: A day\ndescription: Fixture.\n---\n\nWhat happened.\n")
      dir = b.path
      commit_all(dir)
      yield dir
    end
  end

  def test_a_clean_commit_is_append_only
    with_history do |dir|
      File.write(File.join(dir, "journal", "2026-08-12.md"),
        "---\ntype: Journal Entry\ntitle: Today\ndescription: Fixture.\n---\n\nToday.\n")
      git(dir, "add", "-A")

      assert_empty OKF::Pro::Records.staged_violations(dir, today: TODAY)
    end
  end

  # A typechange is not a modification to git — `--diff-filter=MDR` never saw
  # it — and it is the most complete rewrite there is: the day's whole content
  # is replaced by a link to somewhere else. The one artefact nobody can
  # reconstruct, destroyed through the gate written to protect it.
  def test_replacing_a_past_day_with_a_symlink_is_refused
    with_history do |dir|
      path = File.join(dir, "journal", "2026-01-01.md")
      File.write(File.join(dir, "elsewhere.md"), "Not the record.\n")
      File.unlink(path)
      File.symlink("../elsewhere.md", path)
      git(dir, "add", "-A")

      findings = OKF::Pro::Records.staged_violations(dir, today: TODAY)

      assert_equal 1, findings.size
      assert_match(%r{journal/2026-01-01\.md}, findings.first)
      assert_match(/append-only/, findings.first)
    end
  end

  # The bypass this door exists for: no tool event, no guard — but the index
  # still shows the modification.
  def test_modifying_a_past_day_is_refused_however_it_was_written
    with_history do |dir|
      path = File.join(dir, "journal", "2026-01-01.md")
      File.write(path, File.read(path) + "\nRewritten by a shell redirect.\n")
      git(dir, "add", "-A")

      findings = OKF::Pro::Records.staged_violations(dir, today: TODAY)

      assert_equal 1, findings.size
      assert_match(%r{modifies journal/2026-01-01\.md}, findings.first)
      assert_match(/append-only/, findings.first)
    end
  end

  def test_deleting_a_past_day_is_refused
    with_history do |dir|
      File.delete(File.join(dir, "journal", "2026-01-01.md"))
      git(dir, "add", "-A")

      assert_match(%r{deletes journal/2026-01-01\.md},
        OKF::Pro::Records.staged_violations(dir, today: TODAY).first)
    end
  end

  # Today is still being written; the record closes when the day does.
  def test_todays_entry_may_still_change
    with_bundle(git: true) do |b|
      b.write("journal/2026-08-12.md",
        "---\ntype: Journal Entry\ntitle: Today\ndescription: Fixture.\n---\n\nDraft.\n")
      dir = b.path
      commit_all(dir)
      path = File.join(dir, "journal", "2026-08-12.md")
      File.write(path, File.read(path) + "\nMore of today.\n")
      git(dir, "add", "-A")

      assert_empty OKF::Pro::Records.staged_violations(dir, today: TODAY)
    end
  end

  # Creation is the reconstruction the journal guard routes to the owner;
  # this door does not second-guess an approval it cannot see.
  def test_adding_a_missing_past_day_is_not_this_doors_call
    with_history do |dir|
      File.write(File.join(dir, "journal", "2026-02-02.md"),
        "---\ntype: Journal Entry\ntitle: Reconstructed\ndescription: Fixture.\n---\n\nDeclared reconstruction.\n")
      git(dir, "add", "-A")

      assert_empty OKF::Pro::Records.staged_violations(dir, today: TODAY)
    end
  end

  def test_an_unrelated_modification_is_not_a_record
    with_history do |dir|
      path = File.join(dir, "board.md")
      File.write(path, File.read(path) + "\n")
      git(dir, "add", "-A")

      assert_empty OKF::Pro::Records.staged_violations(dir, today: TODAY)
    end
  end

  # The commit door refuses what it cannot check, exactly as dirty_markdown?
  # does — a git that could not answer is not an empty answer.
  def test_a_directory_outside_any_repository_is_refused_not_waved_through
    Dir.mktmpdir do |dir|
      findings = OKF::Pro::Records.staged_violations(dir, today: TODAY)

      assert_equal 1, findings.size
      assert_match(/could not/, findings.first)
      assert_match(/refused rather than waved through/, findings.first)
    end
  end

  def test_no_git_at_all_is_refused
    with_history do |dir|
      original = ENV.fetch("PATH", nil)
      ENV["PATH"] = "/nonexistent"
      begin
        findings = OKF::Pro::Records.staged_violations(dir, today: TODAY)

        assert_equal 1, findings.size
        assert_match(/refused rather than waved through/, findings.first)
      ensure
        ENV["PATH"] = original
      end
    end
  end

  # The verb the pre-commit hook actually calls.
  def test_the_records_verb_fails_loud_and_passes_quiet
    with_history do |dir|
      assert_equal OKF::Pro::PASS, run_cli([ "records", dir ]).status

      path = File.join(dir, "journal", "2026-01-01.md")
      File.write(path, "rewritten\n")
      git(dir, "add", "-A")
      run = run_cli([ "records", dir ])

      assert_equal OKF::Pro::FAIL, run.status
      assert_match(/append-only/, run.err)
    end
  end
end
