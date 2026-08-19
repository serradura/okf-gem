# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"

# The skill has one editable copy — lib/okf/skill, AGENTS.md constraint 6 — and
# two *generated* ones at the repo root: the Claude Code plugin's, and the
# `skills/` tree an installer like `npx skills` reads. One task writes both
# (`rake skill:sync`, which also stamps the gem's version into the plugin
# manifest), so one test guards both; a copy that drifts is a skill shipped to
# somebody at a version nobody edited. Drift is detected by SHA-256: every file
# in the canonical tree must exist in each copy with the same checksum, and no
# extra file may appear there.
class OKF::PluginSyncTest < OKF::TestCase
  # Two roots, named apart on purpose: the canonical skill is the *gem's*, the
  # generated copies are the *repo's*, and a single ROOT that silently meant one
  # or the other is the ambiguity this pairing exists to remove.
  GEM_ROOT = File.expand_path("../..", __dir__)
  REPO_ROOT = File.expand_path("../..", GEM_ROOT)
  CANONICAL = File.join(GEM_ROOT, "lib/okf/skill")
  COPIES = [ "plugin/skills/okf", "skills/okf" ].freeze

  COPIES.each do |rel|
    test "#{rel} carries the same files as lib/okf/skill — run `rake skill:sync` after editing the skill" do
      copy = File.join(REPO_ROOT, rel)

      assert File.directory?(copy), "#{rel} is missing — run `rake skill:sync`"
      assert_equal relative_files(CANONICAL), relative_files(copy)
    end

    test "every skill file in #{rel} matches the canonical checksum — run `rake skill:sync` after editing the skill" do
      relative_files(CANONICAL).each do |name|
        copy = File.join(REPO_ROOT, rel, name)
        next unless File.file?(copy) # the file-list test reports what is missing

        assert_equal checksum(File.join(CANONICAL, name)), checksum(copy),
          "#{rel}/#{name} differs from lib/okf/skill (SHA-256 mismatch) — run `rake skill:sync`"
      end
    end
  end

  test "plugin.json carries the gem version — run `rake skill:sync` after a version bump" do
    manifest = JSON.parse(File.read(File.join(REPO_ROOT, "plugin/.claude-plugin/plugin.json")))
    assert_equal OKF::VERSION, manifest["version"]
  end

  private

  def checksum(path)
    Digest::SHA256.file(path).hexdigest
  end

  def relative_files(root)
    Dir.glob(File.join(root, "**", "*"))
       .select { |path| File.file?(path) }
       .map { |path| path[(root.length + 1)..-1] }
       .sort
  end
end
