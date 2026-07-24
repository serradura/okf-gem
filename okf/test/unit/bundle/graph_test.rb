# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::GraphTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-graph-test")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "builds nodes from concepts only, skipping reserved files" do
    write("features/a.md", fm("Feature", "Alpha") + "See [Beta](b.md).\n")
    write("features/b.md", fm("Feature", "Beta") + "hi\n")
    write("index.md", "# Root\n")
    write("features/index.md", "# Features\n")

    graph = OKF::Bundle::Graph.build(document)

    assert_equal [ "features/a", "features/b" ], graph.nodes.map { |n| n[:id] }.sort
  end

  test "derives edges between existing concepts, dropping ghosts and self-links" do
    write("features/a.md", fm("Feature", "Alpha") + "See [Beta](b.md), [ghost](ghost.md), [me](a.md).\n")
    write("features/b.md", fm("Feature", "Beta") + "hi\n")

    graph = OKF::Bundle::Graph.build(document)

    assert_equal [ { source: "features/a", target: "features/b" } ], graph.edges
  end

  test "dedupes repeated links between the same ordered pair" do
    write("a.md", fm("Feature", "A") + "[b](b.md) and again [b](b.md)\n")
    write("b.md", fm("Feature", "B") + "hi\n")

    assert_equal 1, OKF::Bundle::Graph.build(document).edges.size
  end

  test "applies defaults for missing type and title and non-list tags" do
    write("notes/x.md", "---\ntags: not-a-list\n---\n\nbody text\n")

    node = OKF::Bundle::Graph.build(document).nodes.first

    assert_equal "Untyped", node[:type]
    assert_equal "x", node[:title]
    assert_equal [], node[:tags]
  end

  test "full nodes carry knowledge with the whole body — no presentation fields" do
    write("a.md", fm("Feature", "A") + ("x" * 20_000) + "\n")

    node = OKF::Bundle::Graph.build(document).nodes.first

    assert_equal %i[id type title description tags body].sort, node.keys.sort
    refute node.key?(:sz), "sizing is a render concern, not part of the pure graph"
    assert_equal 20_000, node[:body].length, "the graph keeps the full body; the renderer truncates"
  end

  test "body: false drops the body but keeps the rest" do
    write("a.md", fm("Feature", "A") + "hi\n")

    node = OKF::Bundle::Graph.build(document, body: false).nodes.first

    assert_equal %i[id type title description tags].sort, node.keys.sort
  end

  test "minimal: true keeps only id and title" do
    write("a.md", fm("Feature", "A") + "hi\n")

    node = OKF::Bundle::Graph.build(document, minimal: true).nodes.first

    assert_equal %i[id title], node.keys.sort
  end

  test "type_index and tag_index invert concepts to id lists regardless of fidelity" do
    write("a.md", "---\ntype: Note\ntitle: A\ntags: [x, y]\n---\n\nhi\n")
    write("b.md", "---\ntype: Note\ntitle: B\ntags: [y]\n---\n\nhi\n")

    graph = OKF::Bundle::Graph.build(document, minimal: true)

    assert_equal({ "Note" => %w[a b] }, graph.type_index)
    assert_equal({ "x" => %w[a], "y" => %w[a b] }, graph.tag_index)
  end

  test "a frontmatter id names the node, and inbound links still resolve to it" do
    write("a.md", "---\ntype: Note\ntitle: A\nid: alpha\n---\n\nhi\n")
    write("b.md", fm("Note", "B") + "see [A](a.md)\n")

    graph = OKF::Bundle::Graph.build(document)

    assert_includes graph.nodes.map { |n| n[:id] }, "alpha"
    assert_equal [ { source: "b", target: "alpha" } ], graph.edges
    assert_equal({ "Note" => %w[alpha b] }, graph.type_index)
  end

  test "build is best-effort — a malformed concept is skipped, not fatal" do
    write("good.md", fm("Feature", "Good") + "hi\n")
    write("bad.md", "no frontmatter at all\n")

    graph = nil
    assert_nothing_raised { graph = OKF::Bundle::Graph.build(document) }
    assert_equal [ "good" ], graph.nodes.map { |node| node[:id] }
  end

  test "unlinked_ids lists degree-0 nodes — no cross-links in or out" do
    write("hub.md", fm("Note", "Hub") + "See [leaf](leaf.md).\n") # links out
    write("leaf.md", fm("Note", "Leaf") + "hi\n")                 # linked from hub
    write("loose.md", fm("Note", "Loose") + "no links here\n")    # neither

    graph = OKF::Bundle::Graph.build(document)

    assert_equal %w[loose], graph.unlinked_ids.sort
  end

  test "to_h is JSON-able with nodes and edges" do
    write("a.md", fm("Feature", "A") + "[b](b.md)\n")
    write("b.md", fm("Feature", "B") + "hi\n")

    hash = OKF::Bundle::Graph.build(document).to_h

    assert_equal %i[nodes edges].sort, hash.keys.sort
    assert_kind_of Array, hash[:nodes]
    assert_nothing_raised { require "json"; JSON.generate(hash) }
  end

  private

  def document
    OKF::Bundle::Reader.read(@tmpdir)
  end

  def fm(type, title)
    "---\ntype: #{type}\ntitle: #{title}\n---\n\n"
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
