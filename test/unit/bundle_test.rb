# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::BundleTest < OKF::TestCase
  test "is Concept-first: built straight from Concept objects, no disk, no markdown round-trip" do
    concept = OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note" }, body: "hi")
    bundle = OKF::Bundle.new(concepts: [ concept ])

    assert_equal [ "a" ], bundle.concepts.map(&:id)
    assert_equal [ "a.md" ], bundle.paths
    assert_same concept, bundle.concepts.first
  end

  test "paths span concepts, reserved, and unparseable files, sorted" do
    bundle = OKF::Bundle.new(
      concepts: [ OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note" }, body: "hi") ],
      reserved: [ OKF::Bundle::Entry.new(path: "index.md", content: "# Root"),
                  OKF::Bundle::Entry.new(path: "sub/log.md", content: "## 2026-01-01") ],
      unparseable: [ OKF::Bundle::Entry.new(path: "broken.md", content: "no frontmatter", error: "missing YAML frontmatter") ]
    )

    assert_equal [ "a.md", "broken.md", "index.md", "sub/log.md" ], bundle.paths
    assert_equal [ "a" ], bundle.concepts.map(&:id)
    assert_equal [ "index.md" ], bundle.index_files
    assert_equal [ "sub/log.md" ], bundle.log_files
  end

  test "maps ids to paths and back, honoring a frontmatter id" do
    a = OKF::Concept.new(path: "tables/orders.md", frontmatter: { "id" => "orders", "type" => "Table" }, body: "x")
    b = OKF::Concept.new(path: "notes/n.md", frontmatter: { "type" => "Note" }, body: "y")
    bundle = OKF::Bundle.new(concepts: [ a, b ])

    assert_equal({ "orders" => "tables/orders.md", "notes/n" => "notes/n.md" }, bundle.paths_by_id)
    assert_same a, bundle.concept_by_id("orders")
    assert_nil bundle.concept_by_id("tables/orders"), "the path is no longer the id"
    assert_nil bundle.concept_by_id("missing")
  end

  test "reserved_content returns raw index/log text by path, or empty string" do
    bundle = OKF::Bundle.new(reserved: [ OKF::Bundle::Entry.new(path: "index.md", content: "# Root\n") ])

    assert_equal "# Root\n", bundle.reserved_content("index.md")
    assert_equal "", bundle.reserved_content("missing.md")
  end

  test "convenience methods forward to the pure analyzers" do
    concept = OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note", "title" => "A", "description" => "d" }, body: "hi")
    bundle = OKF::Bundle.new(concepts: [ concept ])

    assert_kind_of OKF::Bundle::Validator::Result, bundle.validate
    assert bundle.validate.valid?
    assert_kind_of OKF::Bundle::Linter::Report, bundle.lint
    assert_kind_of OKF::Bundle::Graph, bundle.graph
  end

  test "resolves relative cross-links in memory via a virtual root when none is given" do
    a = OKF::Concept.new(path: "dir/a.md", frontmatter: { "type" => "Note" }, body: "see [b](./b.md)")
    b = OKF::Concept.new(path: "dir/b.md", frontmatter: { "type" => "Note" }, body: "hi")
    bundle = OKF::Bundle.new(concepts: [ a, b ])

    assert_equal "/okf", bundle.root
    assert_equal [ { source: "dir/a", target: "dir/b" } ], bundle.graph.edges
  end

  test "is pure data — an explicit root is kept verbatim; an empty bundle is empty" do
    bundle = OKF::Bundle.new(root: "/anywhere")

    assert_equal "/anywhere", bundle.root
    assert_empty bundle.concepts
    assert_empty bundle.paths
  end
end
