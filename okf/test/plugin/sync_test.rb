# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"

# The Claude Code plugin carries a *generated* copy of the canonical skill
# (lib/okf/skill stays the single editable source, AGENTS.md constraint 6) and
# the gem's version in its manifest. `rake plugin:sync` regenerates both; this
# fails whenever they drift, so the constraint stays auditable in CI. Drift is
# detected by SHA-256: every file in the canonical tree must exist in the
# plugin copy with the same checksum, and no extra file may appear there.
class OKF::PluginSyncTest < OKF::TestCase
  # Two roots, named apart on purpose: the canonical skill is the *gem's*, the
  # plugin is the *repo's*, and a single ROOT that silently meant one or the
  # other is the ambiguity this pairing exists to remove.
  GEM_ROOT = File.expand_path("../..", __dir__)
  REPO_ROOT = File.expand_path("..", GEM_ROOT)
  CANONICAL = File.join(GEM_ROOT, "lib/okf/skill")
  COPY = File.join(REPO_ROOT, "plugin/skills/okf")

  test "plugin/skills/okf carries the same files as lib/okf/skill — run `rake plugin:sync` after editing the skill" do
    assert File.directory?(COPY), "plugin/skills/okf is missing — run `rake plugin:sync`"
    assert_equal relative_files(CANONICAL), relative_files(COPY)
  end

  test "every skill file in the plugin matches the canonical checksum — run `rake plugin:sync` after editing the skill" do
    relative_files(CANONICAL).each do |rel|
      copy = File.join(COPY, rel)
      next unless File.file?(copy) # the file-list test reports what is missing

      assert_equal checksum(File.join(CANONICAL, rel)), checksum(copy),
        "#{rel} differs from lib/okf/skill (SHA-256 mismatch) — run `rake plugin:sync`"
    end
  end

  test "plugin.json carries the gem version — run `rake plugin:sync` after a version bump" do
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
