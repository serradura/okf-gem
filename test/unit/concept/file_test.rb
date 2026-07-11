# frozen_string_literal: true

require "test_helper"
require "okf"

# OKF::Concept::File — the single-file, ActiveRecord-style disk handle over one
# concept: read, save, reload, delete, with path-safety.
class OKF::Concept::FileTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-concept-file-test")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "reads a concept file from disk into a pure Concept" do
    write("tables/orders.md", "---\ntype: BigQuery Table\ntitle: Orders\n---\n\n# Orders\n")

    file = OKF::Concept::File.read(root: @tmpdir, path: "tables/orders.md")

    assert_equal "tables/orders", file.concept.id
    assert_equal "Orders", file.concept.title
    assert_equal "# Orders\n", file.concept.body
  end

  test "saves a concept's markdown to disk, creating parent directories" do
    concept = OKF::Concept.new(path: "a/b/c.md", frontmatter: { "type" => "Note", "title" => "C" }, body: "# C\n")

    OKF::Concept::File.write(root: @tmpdir, concept: concept)

    content = File.read(File.join(@tmpdir, "a/b/c.md"))
    assert_match(/type: Note/, content)
    assert_match(/# C\n\z/, content)
  end

  test "save then reload round-trips a concept through disk" do
    concept = OKF::Concept.new(path: "x.md", frontmatter: { "type" => "Note", "title" => "X" }, body: "body\n")
    OKF::Concept::File.write(root: @tmpdir, concept: concept)

    reloaded = OKF::Concept::File.read(root: @tmpdir, path: "x.md").concept
    assert_equal "X", reloaded.title
    assert_equal "body\n", reloaded.body
  end

  test "delete removes the file and is idempotent" do
    write("x.md", "---\ntype: Note\n---\n\nhi\n")
    file = OKF::Concept::File.read(root: @tmpdir, path: "x.md")

    file.delete
    refute_path_exists File.join(@tmpdir, "x.md")
    assert_nothing_raised { file.delete } # idempotent
  end

  test "refuses a path that escapes the bundle root" do
    assert_raises(OKF::Path::Error) do
      OKF::Concept::File.new(root: @tmpdir, path: "../escape.md").absolute_path
    end
  end

  private

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
