# frozen_string_literal: true

require "test_helper"

# The same obligation the kernel's packaging_test carries, for the same
# reason: the gem lives in a subdirectory, so the two legal files it must
# distribute are duplicates of the repo root's — real files, never symlinks
# (`gem build` packages a symlink as a symlink, and RubyGems refuses it, or
# worse, extracts it dangling on the old half of the matrix).
class PackagingTest < OKF::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)
  REPO_ROOT = File.expand_path("../..", GEM_ROOT)

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

  # `CLAUDE.md` is one line — `@AGENTS.md` — and `AGENTS.md` is rejected from the
  # gem. Shipping the pointer without its target puts a reference to nothing
  # inside the published gem, where the reader has no checkout to resolve it in.
  #
  # It is not hypothetical tidiness: a new top-level file inside a gem directory
  # ships unless the gemspec rejects it, and this one arrived after the reject
  # list was last read.
  test "CLAUDE.md does not ship — it points at an AGENTS.md the gem does not carry" do
    assert File.file?(File.join(GEM_ROOT, "CLAUDE.md")), "the pointer is missing from the checkout"
    refute_includes spec.files, "CLAUDE.md",
      "CLAUDE.md is in spec.files while AGENTS.md is rejected, so the published gem carries a " \
      "pointer to a file that is not there. Reject both, or ship both."
    refute_includes spec.files, "AGENTS.md"
  end

  # `.okf/` ships on purpose: an installed okf-mcp carries a real bundle for a
  # host to read through its own tools. A new top-level entry inside a gem
  # directory ships unless the gemspec rejects it, so the default here is the
  # one we want — but a default nobody asserted is indistinguishable from an
  # accident, and the next person to prune the reject list has nothing to read.
  test ".okf/ ships — the gem carries its own bundle, deliberately" do
    shipped = spec.files.grep(%r{\A\.okf/})
    refute_empty shipped, ".okf/ is not in spec.files: the published gem carries no bundle of its own"
    assert_includes shipped, ".okf/index.md", "a bundle without its index is not a bundle"
  end

  private

  def spec
    @spec ||= Dir.chdir(GEM_ROOT) { Gem::Specification.load(File.join(GEM_ROOT, "okf-mcp.gemspec")) }
  end
end
