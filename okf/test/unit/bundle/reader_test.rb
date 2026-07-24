# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::ReaderTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-reader-test")
    write("tables/orders.md", <<~MD)
      ---
      type: BigQuery Table
      title: Orders
      ---

      # Orders
    MD
    write("references/vendor/api.md", <<~MD)
      ---
      type: API Reference
      ---

      # Vendor API
    MD
    write("index.md", "# Catalog\n")
    write("groups/log.md", "## 2026-06-26\n")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "reads the bundle into an OKF::Bundle with an absolute root" do
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_kind_of OKF::Bundle, bundle
    assert_equal File.expand_path(@tmpdir), bundle.root
    assert_equal [ "groups/log.md", "index.md", "references/vendor/api.md", "tables/orders.md" ], bundle.paths
  end

  test "parses nested concept ids from the bundle, skipping reserved files" do
    ids = OKF::Bundle::Reader.read(@tmpdir).concepts.map(&:id)

    assert_equal [ "references/vendor/api", "tables/orders" ], ids
  end

  test "carries frontmatter and body on each concept" do
    concept = OKF::Bundle::Reader.read(@tmpdir).concepts.find { |c| c.id == "tables/orders" }

    assert_equal "tables/orders.md", concept.path
    assert_equal "BigQuery Table", concept.type
    assert_equal "Orders", concept.title
    assert_equal "# Orders\n", concept.body
  end

  test "exposes reserved files through the bundle" do
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_equal [ "index.md" ], bundle.index_files
    assert_equal [ "groups/log.md" ], bundle.log_files
  end

  test "an empty or missing directory reads as an empty bundle" do
    missing = OKF::Bundle::Reader.read(File.join(@tmpdir, "nope"))

    assert_empty missing.paths
    assert_empty missing.concepts
  end

  test "a concept file that fails to parse lands in unparseable, not raised or dropped" do
    write("broken.md", "no frontmatter here\n")
    bundle = OKF::Bundle::Reader.read(@tmpdir)

    assert_equal [ "references/vendor/api", "tables/orders" ], bundle.concepts.map(&:id)
    assert_equal [ "broken.md" ], bundle.unparseable.map(&:path)
    assert_equal "missing YAML frontmatter", bundle.unparseable.first.error
    assert_includes bundle.paths, "broken.md"
  end

  private

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
