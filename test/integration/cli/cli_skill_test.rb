# frozen_string_literal: true

require_relative "cli_integration_case"

# `okf skill <dest>` end-to-end — installs the gem's bundled companion skill into
# a destination directory. The skill ships inside the gem (skill/assets/okf), so
# these assert the CLI copies it faithfully and guards an existing destination.
class CLISkillTest < CLIIntegrationCase
  ASSETS = OKF::Skill::ASSETS

  test "installs the whole skill tree and reports what it wrote" do
    dest = File.join(@out_dir, "okf")
    result = okf("skill", dest)

    assert_equal 0, result.status
    assert_match(/installed the okf skill \(9 files\)/, result.out)
    # Every asset file lands at the destination, byte-for-byte.
    Dir.glob(File.join(ASSETS, "**", "*")).select { |path| File.file?(path) }.map { |path| path[(ASSETS.length + 1)..-1] }.each do |rel|
      copied = File.join(dest, rel)
      assert File.file?(copied), "expected #{rel} to be installed"
      assert_equal File.read(File.join(ASSETS, rel)), File.read(copied), "#{rel} content differs"
    end
  end

  test "nests the skill under okf/ when pointed at a skills dir" do
    dest = File.join(@out_dir, "skills")
    result = okf("skill", dest)

    installed = File.join(dest, "okf")
    assert_equal 0, result.status
    assert File.file?(File.join(installed, "SKILL.md")), "expected the skill under skills/okf"
    assert_match(/-> #{Regexp.escape(installed)}\b/, result.out)
    refute File.file?(File.join(dest, "SKILL.md")), "must not splatter files loose in the skills dir"
  end

  test "a destination already named okf is used as-is (no okf/okf)" do
    dest = File.join(@out_dir, "skills", "okf")
    result = okf("skill", dest)

    assert_equal 0, result.status
    assert File.file?(File.join(dest, "SKILL.md"))
    refute File.directory?(File.join(dest, "okf")), "must not double-nest okf/okf"
  end

  test "--here installs straight into the destination without nesting" do
    dest = File.join(@out_dir, "skills")
    result = okf("skill", dest, "--here")

    assert_equal 0, result.status
    assert File.file?(File.join(dest, "SKILL.md")), "expected files straight in the given dir"
    refute File.directory?(File.join(dest, "okf")), "--here must not nest an okf/ folder"
  end

  test "a missing destination is a usage error (exit 2)" do
    result = okf("skill")

    assert_equal 2, result.status
    assert_match(%r{Usage: okf skill <dest-dir>}, result.err)
  end

  test "refuses to overwrite a non-empty destination without --force" do
    dest = File.join(@out_dir, "okf")
    FileUtils.mkdir_p(dest)
    File.write(File.join(dest, "keep.md"), "mine")

    result = okf("skill", dest)

    assert_equal 2, result.status
    assert_match(/not empty/, result.err)
    assert_equal "mine", File.read(File.join(dest, "keep.md")) # untouched
  end

  test "--force overwrites a non-empty destination" do
    dest = File.join(@out_dir, "okf")
    FileUtils.mkdir_p(dest)
    File.write(File.join(dest, "keep.md"), "mine")

    result = okf("skill", dest, "--force")

    assert_equal 0, result.status
    assert File.file?(File.join(dest, "SKILL.md"))
  end
end
