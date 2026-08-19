# frozen_string_literal: true

require "test_helper"

# `okf pro setup` through dispatch: the exit codes, the report a person reads,
# and the two states it must not silently create.
class CLISetupTest < OKF::Pro::TestCase
  def test_setup_into_an_empty_directory_writes_the_whole_tree_and_exits_zero
    Dir.mktmpdir do |dir|
      run = run_cli([ "setup", dir ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/#{template_files} written, 0 staged/, run.out)
      assert File.file?(File.join(dir, ".okf", "board.md"))
      assert File.file?(File.join(dir, ".claude", "hooks", "run"))
      assert File.file?(File.join(dir, ".githooks", "pre-commit"))
      assert File.file?(File.join(dir, ".github", "workflows", "okf-pro.yml"))
    end
  end

  # Idempotent and re-runnable is the whole of the atomicity story: each file is
  # written to a temp path and renamed, so no half-written file exists, but a
  # nineteen-file sequence is not atomic as a set and nothing here pretends it
  # is. Running it again is what makes an interrupted run harmless.
  def test_setup_run_twice_changes_nothing
    Dir.mktmpdir do |dir|
      run_cli([ "setup", dir ])
      before = tree(dir)

      run = run_cli([ "setup", dir ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/0 written, 0 staged, #{template_files} left alone/, run.out)
      assert_equal before, tree(dir)
    end
  end

  # It writes what it can and never refuses wholesale. A repo that already has
  # a CLAUDE.md is the common case, not an error.
  def test_a_collision_is_staged_beside_the_adopters_file_and_still_exits_zero
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "CLAUDE.md"), "mine\n")

      run = run_cli([ "setup", dir ])

      assert_equal OKF::Pro::PASS, run.status
      assert_equal "mine\n", File.read(File.join(dir, "CLAUDE.md")), "the adopter's file is untouched"
      assert File.file?(File.join(dir, "CLAUDE.md.okf-pro-new"))
      assert_match(/Merge what you want from each/, run.out)
    end
  end

  # The closing line of the collision report is a claim about the reader's own
  # tree, and it is false in exactly the case that matters. When `.gitignore` is
  # itself a collision, the adopter's own file is what stays on disk — and it
  # does not carry the `*.okf-pro-new` line, because the template's copy went to
  # `.gitignore.okf-pro-new` with everything else. Telling them it is ignored is
  # how the staged files get committed with nothing ever saying so, which is the
  # failure the seeded `.gitignore` comment exists to prevent.
  def test_the_ignore_claim_is_not_made_when_the_adopters_gitignore_does_not_ignore_them
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".gitignore"), "node_modules/\n")

      run = run_cli([ "setup", dir ])

      assert_equal OKF::Pro::PASS, run.status
      refute_match(/already ignores/, run.out,
        "the adopter's .gitignore does not ignore the staged files, and saying it does is how they get committed")
      assert_match(/\*#{Regexp.escape(OKF::Pro::Scaffold::SUFFIX)}/, run.out,
        "it must still name the line to add, or the reader is left to work it out")
    end
  end

  def test_the_ignore_claim_is_made_when_setup_wrote_the_gitignore_itself
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "CLAUDE.md"), "mine\n")

      run = run_cli([ "setup", dir ])

      assert_match(/already ignores/, run.out,
        "setup wrote the .gitignore, so the claim is true and worth making")
    end
  end

  def test_a_stale_staged_file_is_refreshed_rather_than_doubled
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "CLAUDE.md"), "mine\n")
      run_cli([ "setup", dir ])
      File.write(File.join(dir, "CLAUDE.md.okf-pro-new"), "an older template\n")

      run_cli([ "setup", dir ])

      refute File.exist?(File.join(dir, "CLAUDE.md.okf-pro-new.okf-pro-new")),
        "a second collision must refresh the staged file, not stage the staged file"
      assert_match(/^# What this repo is/, OKF::Pro.read_text(File.join(dir, "CLAUDE.md.okf-pro-new")))
    end
  end

  # A bundle that already exists is a bundle already adopted. Eleven shadow
  # files scattered through someone's knowledge is not a merge prompt, it is
  # litter — in the one directory whose whole value is that everything in it was
  # put there deliberately.
  def test_an_existing_bundle_gets_its_missing_files_and_no_shadow_copies
    Dir.mktmpdir do |dir|
      run_cli([ "setup", dir ])
      bundle = File.join(dir, ".okf")
      File.write(File.join(bundle, "board.md"), OKF::Pro.read_text(File.join(bundle, "board.md")) + "\n- mine\n")
      File.unlink(File.join(bundle, "roadmap.md"))

      run_cli([ "setup", dir ])

      assert File.file?(File.join(bundle, "roadmap.md")), "a missing file is restored"
      assert_match(/- mine/, OKF::Pro.read_text(File.join(bundle, "board.md")), "an edited one is left alone")
      assert_empty Dir.glob(File.join(bundle, "**", "*.okf-pro-new"), File::FNM_DOTMATCH)
    end
  end

  # The exemption is asked of the path *within* the destination, not of the
  # absolute one. `~/.okf/notes` is a plausible enough place to keep a
  # repository that getting this wrong is worth a test: asked absolutely, every
  # file under it lands on the exempt side and a collision on CLAUDE.md is
  # silently kept instead of staged.
  def test_a_destination_living_under_a_dot_okf_directory_still_stages_collisions
    Dir.mktmpdir do |root|
      dir = File.join(root, ".okf", "my-notes")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "CLAUDE.md"), "mine\n")

      run = run_cli([ "setup", dir ])

      assert_equal OKF::Pro::PASS, run.status
      assert File.file?(File.join(dir, "CLAUDE.md.okf-pro-new")),
        "the exemption is about this bundle, not about a parent directory's name"
    end
  end

  # Writing `.okf/index.md` beside a root-level bundle collides with nothing, so
  # the naive generator succeeds and leaves two bundle roots in one directory —
  # the state `Audit.ambiguous_layout` exists to report, where the three doors
  # disagree until one of the two is retired.
  def test_setup_into_a_flat_layout_bundle_refuses_and_names_the_migration
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.md"), "---\nokf_version: \"0.2\"\n---\n\n# Flat\n")

      run = run_cli([ "setup", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/already an OKF bundle at its own root/, run.err)
      assert_match(/git mv/, run.err)
      refute File.exist?(File.join(dir, ".okf")), "nothing may be written on the refusal path"
    end
  end

  private

  # Derived, not typed: a count in a literal is a test edit every time the
  # template grows a file, and the thing worth asserting is that setup wrote
  # *all* of them. Which files those are is scaffold_test's business.
  def template_files
    %w[gem seed].sum { |half| OKF::Pro::Scaffold.entries(File.join(OKF::Pro::Scaffold::ROOT, half)).size }
  end

  def tree(dir)
    Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
       .select { |p| File.file?(p) }.sort
       .map { |p| [ p.sub("#{dir}/", ""), File.binread(p), File.stat(p).mode ] }
  end
end
