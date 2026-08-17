# frozen_string_literal: true

require "test_helper"

# `okf pro upgrade` — the one thing the generator may safely do twice.
#
# The split it enforces is by OWNERSHIP, not by subject matter. Classing
# CLAUDE.md, .gitignore and settings.json as "machinery" is the obvious cut and
# the wrong one: they are the adopter's own files from the moment they are
# seeded, and an upgrade that rewrote them would destroy exactly the hand-merge
# that adopting this thing asked for.
class CLIUpgradeTest < OKF::Pro::TestCase
  GEM_OWNED = [
    ".claude/hooks/run",
    ".githooks/pre-commit",
    ".github/workflows/okf-pro.yml",
    ".claude/skills/okf-pro/SKILL.md"
  ].freeze

  SEEDED = [ "CLAUDE.md", ".gitignore", ".claude/settings.json", ".okf/board.md", ".okf/index.md" ].freeze

  def test_the_four_gem_owned_files_are_rewritten
    Dir.mktmpdir do |dir|
      run_cli([ "setup", dir ])
      GEM_OWNED.each { |rel| File.write(File.join(dir, rel), "stale\n") }

      run = run_cli([ "upgrade", dir ])

      assert_equal OKF::Pro::PASS, run.status
      GEM_OWNED.each do |rel|
        refute_equal "stale\n", OKF::Pro.read_text(File.join(dir, rel)),
          "#{rel} carries the contract and must track the gem"
      end
    end
  end

  def test_every_seeded_file_survives_byte_for_byte
    Dir.mktmpdir do |dir|
      run_cli([ "setup", dir ])
      SEEDED.each { |rel| File.write(File.join(dir, rel), "the adopter's own #{rel}\n") }

      run_cli([ "upgrade", dir ])

      SEEDED.each do |rel|
        assert_equal "the adopter's own #{rel}\n", OKF::Pro.read_text(File.join(dir, rel)),
          "#{rel} is the adopter's from the moment it is seeded"
      end
    end
  end

  # The hook wrapper is written back executable, not merely written back. git
  # silently skips a non-executable hook and the shell reports 127, which the
  # hook protocol reads as non-blocking — so a mode lost in an upgrade is every
  # gate switched off, with the correct content on disk.
  def test_the_rewritten_scripts_keep_their_executable_bit
    Dir.mktmpdir do |dir|
      run_cli([ "setup", dir ])
      OKF::Pro::Scaffold::EXECUTABLE.each { |rel| File.chmod(0o644, File.join(dir, rel)) }

      run_cli([ "upgrade", dir ])

      OKF::Pro::Scaffold::EXECUTABLE.each do |rel|
        assert File.executable?(File.join(dir, rel)), "#{rel} came back without +x"
      end
    end
  end

  def test_upgrading_a_directory_that_is_not_one_refuses
    Dir.mktmpdir do |dir|
      file = File.join(dir, "not-a-dir")
      File.write(file, "")

      run = run_cli([ "upgrade", file ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/is not a directory/, run.err)
    end
  end

  # An upgrade of a tree that was never set up completes it rather than
  # refusing: a half-adopted repo is the state an interrupted setup leaves, and
  # the fix for it should not be a different verb.
  def test_upgrade_completes_a_tree_that_was_never_set_up
    Dir.mktmpdir do |dir|
      run = run_cli([ "upgrade", dir ])

      assert_equal OKF::Pro::PASS, run.status
      assert File.file?(File.join(dir, ".okf", "board.md"))
    end
  end
end
