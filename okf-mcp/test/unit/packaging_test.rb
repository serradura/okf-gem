# frozen_string_literal: true

require "test_helper"

# The same obligation the kernel's packaging_test carries, for the same
# reason: the gem lives in a subdirectory, so the two legal files it must
# distribute are duplicates of the repo root's — real files, never symlinks
# (`gem build` packages a symlink as a symlink, and RubyGems refuses it, or
# worse, extracts it dangling on the old half of the matrix).
class PackagingTest < OKF::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)
  REPO_ROOT = File.expand_path("..", GEM_ROOT)

  [ "LICENSE.txt", "NOTICE" ].each do |name|
    test "#{name} is a real file, not a symlink — a symlinked one builds fine and refuses to install" do
      path = File.join(GEM_ROOT, name)
      assert File.exist?(path), "#{name} is missing from the gem directory"
      refute File.symlink?(path), "#{name} is a symlink: gem install would raise Gem::Package::SymlinkError"
    end

    test "#{name} is byte-identical to the repo root's copy" do
      assert_equal File.binread(File.join(REPO_ROOT, name)), File.binread(File.join(GEM_ROOT, name)),
        "#{name} has drifted from the repo root's copy — they must stay identical"
    end

    test "#{name} is in spec.files, so it actually ships" do
      assert_includes spec.files, name, "#{name} is not in spec.files — the gem would ship without it"
    end
  end

  private

  def spec
    @spec ||= Dir.chdir(GEM_ROOT) { Gem::Specification.load(File.join(GEM_ROOT, "okf-mcp.gemspec")) }
  end
end
