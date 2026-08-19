# frozen_string_literal: true

require "test_helper"

# `okf pro skill <dest>` — the skill on its own, for a repo that governs its
# bundle with this gem's rules but keeps its own everything else.
class CLISkillTest < OKF::Pro::TestCase
  # The skill is a directory, not a file. It was one file when this verb was
  # written, and an installer that keeps copying only SKILL.md after the skill
  # grows guides installs something that *looks* installed: the entry point is
  # there, its index lists five guides, and every link in it is dead. Nothing
  # errors — the agent simply cannot follow its own instructions.
  def test_every_file_the_skill_ships_is_installed_not_only_the_entry_point
    Dir.mktmpdir do |dest|
      assert_equal OKF::Pro::PASS, run_cli([ "skill", dest ]).status

      source = File.join(OKF::Pro::Scaffold::GEM_DIR, File.dirname(OKF::Pro::Scaffold::SKILL_REL))
      shipped = OKF::Pro::Scaffold.entries(source)
      installed = OKF::Pro::Scaffold.entries(dest)

      assert_equal shipped, installed,
        "the skill ships #{shipped.size} file(s) and #{installed.size} were installed"
    end
  end

  def test_installs_the_skill_at_the_named_destination
    Dir.mktmpdir do |dir|
      dest = File.join(dir, "skills", "okf-pro")

      run = run_cli([ "skill", dest ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/^name: okf-pro$/, OKF::Pro.read_text(File.join(dest, "SKILL.md")))
    end
  end

  # Unlike the seeded files, this one is overwritten: it is gem-owned, and the
  # verb exists precisely to refresh it.
  def test_reinstalling_overwrites_the_previous_copy
    Dir.mktmpdir do |dir|
      dest = File.join(dir, "okf-pro")
      run_cli([ "skill", dest ])
      File.write(File.join(dest, "SKILL.md"), "stale\n")

      run_cli([ "skill", dest ])

      refute_equal "stale\n", OKF::Pro.read_text(File.join(dest, "SKILL.md"))
    end
  end

  # `.claude/skills/okf-pro` is the natural destination and `.claude/skills`
  # usually does not exist yet, so the tree is created. Refusing on a missing
  # parent would refuse the common case to guard against a typo costing one
  # `rm -r`.
  def test_a_destination_several_levels_deep_is_created
    Dir.mktmpdir do |dir|
      dest = File.join(dir, ".claude", "skills", "okf-pro")

      assert_equal OKF::Pro::PASS, run_cli([ "skill", dest ]).status
      assert File.file?(File.join(dest, "SKILL.md"))
    end
  end

  def test_a_destination_that_is_a_file_refuses
    Dir.mktmpdir do |dir|
      dest = File.join(dir, "okf-pro")
      File.write(dest, "")

      run = run_cli([ "skill", dest ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/is a file/, run.err)
    end
  end

  def test_no_destination_refuses_rather_than_guessing
    run = run_cli([ "skill" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/needs a destination directory/, run.err)
  end
end
