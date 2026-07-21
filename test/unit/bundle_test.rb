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

  test "hubs ranks concepts by inbound degree with the source areas each link comes from" do
    core = OKF::Concept.new(path: "core/status.md", frontmatter: { "type" => "Reference" }, body: "the hub")
    a = OKF::Concept.new(path: "flows/a.md", frontmatter: { "type" => "Flow" }, body: "see [s](/core/status.md)")
    b = OKF::Concept.new(path: "flows/b.md", frontmatter: { "type" => "Flow" }, body: "see [s](/core/status.md) and [a](/flows/a.md)")
    root = OKF::Concept.new(path: "note.md", frontmatter: { "type" => "Note" }, body: "see [s](/core/status.md)")
    bundle = OKF::Bundle.new(concepts: [ core, a, b, root ])

    assert_equal [
      { id: "core/status", area: "core", inbound: 3, by_area: { "flows" => 2, "(root)" => 1 } },
      { id: "flows/a", area: "flows", inbound: 1, by_area: { "flows" => 1 } }
    ], bundle.hubs
  end

  test "hubs is empty when nothing links, and pure — no disk involved" do
    bundle = OKF::Bundle.new(concepts: [ OKF::Concept.new(path: "a.md", frontmatter: { "type" => "Note" }, body: "hi") ])

    assert_equal [], bundle.hubs
  end

  test "directory_index groups concepts by file-path directory, root first, with type/tag rollups" do
    bundle = OKF::Bundle.new(
      concepts: [
        OKF::Concept.new(path: "overview.md", frontmatter: { "type" => "Overview", "title" => "Ov", "tags" => [ "x" ] }, body: ""),
        OKF::Concept.new(path: "svc/a.md", frontmatter: { "type" => "Service", "title" => "A", "tags" => %w[x y] }, body: ""),
        OKF::Concept.new(path: "svc/b.md", frontmatter: { "type" => "Service", "title" => "B", "tags" => [ "y" ] }, body: "")
      ],
      reserved: [ OKF::Bundle::Entry.new(path: "index.md", content: %(---\nokf_version: "0.1"\n---\n\n# Root listing\n)) ]
    )

    map = bundle.directory_index
    assert_equal [ ".", "svc" ], map.map { |entry| entry[:dir] }, "root sorts first"
    root, svc = map

    assert_equal 1, root[:count]
    assert_equal [ "svc" ], root[:subdirs]
    assert_equal true, root[:present]
    assert_equal "# Root listing\n", root[:body], "root index frontmatter is stripped"

    assert_equal 2, svc[:count]
    assert_equal false, svc[:present]
    assert_equal true, svc[:synthesized]
    assert_equal({ "Service" => 2 }, svc[:types])
    assert_equal({ "y" => 2, "x" => 1 }, svc[:tags], "tags order by count desc then name")
    assert_equal [ "svc/a", "svc/b" ], svc[:listing].map { |item| item[:id] }, "listing present even without an index.md"
    assert_nil svc[:body]
  end

  test "directory_index groups by file path, not by a custom frontmatter id" do
    concept = OKF::Concept.new(path: "tables/orders.md", frontmatter: { "id" => "orders", "type" => "Table" }, body: "")
    bundle = OKF::Bundle.new(concepts: [ concept ])

    tables = bundle.directory_index.find { |entry| entry[:dir] == "tables" }
    assert tables, "a custom id must not collapse the concept into the root"
    assert_equal [ "orders" ], tables[:listing].map { |item| item[:id] }
  end

  test "directory_index keeps a nested index (no frontmatter) verbatim and never raises on it" do
    bundle = OKF::Bundle.new(
      concepts: [ OKF::Concept.new(path: "svc/a.md", frontmatter: { "type" => "Service" }, body: "") ],
      reserved: [ OKF::Bundle::Entry.new(path: "svc/index.md", content: "# Services\n\n* [A](a.md)\n") ]
    )

    svc = bundle.directory_index.find { |entry| entry[:dir] == "svc" }
    assert_equal true, svc[:present]
    assert_equal "# Services\n\n* [A](a.md)\n", svc[:body]
  end

  test "directory_index connects nested directories through empty intermediates" do
    bundle = OKF::Bundle.new(concepts: [ OKF::Concept.new(path: "a/b/c.md", frontmatter: { "type" => "Note" }, body: "") ])

    map = bundle.directory_index
    assert_equal [ ".", "a", "a/b" ], map.map { |entry| entry[:dir] }
    assert_equal [ "a" ], map[0][:subdirs]
    assert_equal [ "a/b" ], map[1][:subdirs]
    assert_equal 1, map[2][:count]
  end

  test "directory_index shows a directory that carries only an index.md" do
    bundle = OKF::Bundle.new(reserved: [ OKF::Bundle::Entry.new(path: "index.md", content: "# Just a map\n") ])

    map = bundle.directory_index
    assert_equal [ "." ], map.map { |entry| entry[:dir] }
    assert_equal true, map.first[:present]
    assert_equal 0, map.first[:count]
  end

  test "directory_index is empty for a bundle with no concepts or index files" do
    assert_empty OKF::Bundle.new.directory_index
  end
end
