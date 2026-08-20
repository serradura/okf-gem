# frozen_string_literal: true

require "test_helper"
require "okf"

# The one shell-side containment primitive every bundle read goes through.
class OKF::SafeReadTest < OKF::TestCase
  setup do
    @root = Dir.mktmpdir("okf-safe-read")
    @outside = Dir.mktmpdir("okf-safe-read-outside")
    File.write(File.join(@root, "real.md"), "inside\n")
    File.write(File.join(@outside, "secret"), "OUTSIDE\n")
  end

  teardown do
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@outside)
  end

  test "reads a real in-root file" do
    assert_equal "inside\n", OKF::SafeRead.read!(@root, File.join(@root, "real.md"))
  end

  test "follows a symlink that stays inside the root" do
    File.symlink(File.join(@root, "real.md"), File.join(@root, "alias.md"))
    assert_equal "inside\n", OKF::SafeRead.read!(@root, File.join(@root, "alias.md"))
  end

  test "refuses a symlink whose target escapes the root" do
    File.symlink(File.join(@outside, "secret"), File.join(@root, "escape.md"))
    error = assert_raises(OKF::Path::Error) { OKF::SafeRead.read!(@root, File.join(@root, "escape.md")) }
    assert_match(/escapes bundle root/, error.message)
  end

  test "reads the resolved path, not the caller's unresolved name" do
    File.symlink(File.join(@root, "real.md"), File.join(@root, "alias.md"))
    resolved = OKF::SafeRead.contained_path!(@root, File.join(@root, "alias.md"))
    assert_equal File.realpath(File.join(@root, "real.md")), resolved
  end

  test "Path.under? admits children of the filesystem root" do
    assert OKF::Path.under?("/", "/")
    assert OKF::Path.under?("/", "/index.md")
    assert OKF::Path.under?("/", "/a/b.md")
  end

  test "Path.under? still rejects a sibling that shares a prefix" do
    refute OKF::Path.under?("/foo", "/food")
    refute OKF::Path.under?("/foo", "/foobar/x")
  end
end
