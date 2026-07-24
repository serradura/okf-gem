# frozen_string_literal: true

require "test_helper"

# The gem lives in a subdirectory of the repo, so the two legal files it is
# obliged to distribute cannot be the repo's own — `git ls-files` from here never
# sees them. They are duplicated into the gem instead of symlinked, and that is
# not a style choice: `gem build` writes a symlink into the package *as a
# symlink*, and RubyGems then refuses to extract one pointing outside the gem
# (Gem::Package::SymlinkError). The build succeeds, the spec lists the file, and
# the failure lands on a user's machine at `gem install`. So: real files, and
# these assertions instead of the drift a duplicate would otherwise invite.
class OKF::PackagingTest < OKF::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)
  REPO_ROOT = File.expand_path("..", GEM_ROOT)

  [ "LICENSE.txt", "NOTICE" ].each do |name|
    test "#{name} is a real file, not a symlink — a symlinked one builds fine and refuses to install" do
      path = File.join(GEM_ROOT, name)
      assert File.exist?(path), "#{name} is missing from the gem directory"
      refute File.symlink?(path), "#{name} is a symlink: gem install would raise Gem::Package::SymlinkError"
    end

    test "#{name} is byte-identical to the repo's copy" do
      assert_equal File.binread(File.join(REPO_ROOT, name)), File.binread(File.join(GEM_ROOT, name)),
        "#{name} has drifted from the repo root's copy — they must stay identical"
    end

    # The file existing is not the obligation; the file *shipping* is. Present
    # but untracked, or newly caught by the gemspec's reject list, and the gem
    # goes out without the licence it is required to distribute — with all the
    # assertions above still green.
    test "#{name} is in spec.files, so it actually ships" do
      assert_includes spec.files, name, "#{name} is not in spec.files — the gem would ship without it"
    end
  end

  private

  def spec
    # Loaded from the gem's own directory: spec.files comes from `git ls-files`
    # with chdir, so the working directory it is evaluated in decides the answer.
    @spec ||= Dir.chdir(GEM_ROOT) { Gem::Specification.load(File.join(GEM_ROOT, "okf.gemspec")) }
  end
end
