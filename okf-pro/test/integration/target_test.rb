# frozen_string_literal: true

require "test_helper"

# Which edits a check applies to at all.
#
# `Target.for` returns nil whenever a check cannot apply, and nil is a real
# answer rather than a failure: a check that does not apply has nothing to
# say, which is different from passing something it could not read. Every
# check distinguishes the two, so this boundary is worth pinning on its own.
class TargetTest < OKF::Pro::TestCase
  def test_files_behind_a_dot_are_outside_the_bundle
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_nil OKF::Pro::Target.for(edit_event(b.path, ".tmp/scratch.md"))
      assert_nil OKF::Pro::Target.for(edit_event(b.path, ".claude/settings.md"))
    end
  end

  def test_non_markdown_is_outside
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")

      assert_nil OKF::Pro::Target.for(edit_event(b.path, "script.rb"))
    end
  end

  def test_a_directory_that_is_not_a_bundle_is_outside
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "notes.md"), "# Notes\n")

      assert_nil OKF::Pro::Target.for(edit_event(dir, "notes.md"))
    end
  end

  def test_a_path_outside_the_root_is_outside
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      e = event(tool_name: "Edit", cwd: b.path, tool_input: { file_path: "/elsewhere/other.md" })

      assert_nil OKF::Pro::Target.for(e)
    end
  end

  # An absolute path can pass through a dot-directory that has nothing to do
  # with the file — /Users/someone/.local/share/... — so the dot test has to
  # run on the path relative to the bundle root, not the whole thing.
  def test_a_dot_in_the_path_above_the_root_is_not_a_dot_path
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      target = OKF::Pro::Target.for(edit_event(b.path, "glossary/term.md"))

      refute_nil target
      assert_equal "glossary/term.md", target.rel
      assert_equal "glossary/term", target.id
    end
  end

  # The fence, end to end: containing() refuses a file inside a nested
  # repository, and there is no cwd fallback left to re-adopt it. The old
  # `|| resolve(event.cwd)` did exactly that whenever the session sat in a
  # root-layout bundle — resolve neither walks nor fences, and relative()
  # checks only physical prefix.
  def test_a_file_in_a_nested_repository_is_not_adopted_via_the_cwd
    with_bundle(git: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path
      vendor = File.join(dir, "vendor", "thing")
      FileUtils.mkdir_p(File.join(vendor, ".git"))
      File.write(File.join(vendor, "notes.md"), "# Notes\n")

      event = OKF::Pro::Event.new(JSON.generate(
        "tool_name" => "Write", "cwd" => dir,
        "tool_input" => { "file_path" => File.join(vendor, "notes.md") }
      ))

      assert_nil OKF::Pro::Target.for(event)
    end
  end

  def test_a_file_inside_the_bundle_needs_no_cwd_to_be_governed
    with_bundle(git: true) do |b|
      b.concept("glossary/term.md", type: "Term")
      dir = b.path

      event = OKF::Pro::Event.new(JSON.generate(
        "tool_name" => "Write", "cwd" => "/",
        "tool_input" => { "file_path" => File.join(dir, "glossary", "term.md") }
      ))

      target = OKF::Pro::Target.for(event)

      refute_nil target
      assert_equal "glossary/term.md", target.rel
    end
  end

  # root? accepts any core file beside a frontmatterless index (the okf
  # format allows one), so even a mid-bootstrap bundle — index and board
  # down, log.md not yet written — governs its files. Demanding the full
  # skeleton let a `verified:` attestation land unguarded, in silence,
  # while the bundle was half-built.
  def test_a_mid_bootstrap_bundle_still_governs_its_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "index.md"), "# My bundle\n")
      File.write(File.join(dir, "board.md"), "# Board\n")
      FileUtils.mkdir_p(File.join(dir, "glossary"))
      file = File.join(dir, "glossary", "term.md")
      File.write(file, "# Term\n")

      event = OKF::Pro::Event.new(JSON.generate(
        "tool_name" => "Write", "cwd" => "/",
        "tool_input" => { "file_path" => file }
      ))
      target = OKF::Pro::Target.for(event)

      refute_nil target
      assert_equal "glossary/term.md", target.rel
    end
  end
end
