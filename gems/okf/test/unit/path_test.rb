# frozen_string_literal: true

require "test_helper"
require "okf"

# The bundle's path-traversal guard. Bundle::Reader, Bundle::Writer, and
# Concept::File route every filesystem path through these, so a symlinked or
# crafted path can never escape the bundle root.
class OKF::PathTest < OKF::TestCase
  test "normalize_relative! rejects unsafe paths" do
    [
      "",                # blank
      "/etc/passwd.md",  # absolute
      "a/../b.md",       # parent traversal
      "./a.md",          # current-dir segment
      "a//b.md",         # empty segment
      "a\\b.md",         # backslash
      "bad\0.md"         # null byte
    ].each do |path|
      assert_raises(OKF::Path::Error, path.inspect) { OKF::Path.normalize_relative!(path) }
    end
  end

  test "normalize_relative! passes and canonicalizes a clean relative path" do
    assert_equal "tables/orders.md", OKF::Path.normalize_relative!("tables/orders.md")
  end

  test "join_under! rejects a path that escapes the root" do
    assert_raises(OKF::Path::Error) { OKF::Path.join_under!("/bundle", "../secrets.md") }
  end

  test "join_under! returns an absolute path inside the root" do
    assert_equal "/bundle/tables/orders.md", OKF::Path.join_under!("/bundle", "tables/orders.md")
  end
end
