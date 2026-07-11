# frozen_string_literal: true

require "test_helper"

require "json"

require "okf"
require "okf/server/app"

class OKF::Server::GraphTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-viz-test")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "renders a self-contained page booting from a minimal, body-free payload" do
    write("a.md", "---\ntype: Feature\ntitle: Alpha\n---\n\n[Beta](b.md)\n" + ("x" * 5000))
    write("b.md", "---\ntype: Feature\ntitle: Beta\n---\n\nhi\n")

    html = render(title: "Demo")

    assert_includes html, "<!doctype html"
    assert_includes html, "Demo"
    assert_includes html, %("id":"a")
    assert_includes html, %("source":"a")
    nodes = JSON.parse(html[/const NODES=(\[.*?\]), EDGES=/m, 1])
    assert_equal [ %w[id title] ], nodes.map { |n| n.keys.sort }.uniq, "nodes ship lean — id + title only"
    refute_includes html, "x" * 5000, "a concept body is never embedded"
  end

  test "loads cytoscape and marked and wires the on-demand endpoints" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    assert_includes html, "cytoscape"
    assert_includes html, "marked"
    refute_includes html, "htmx", "htmx was dropped — the page fetches bodies with fetch()"
    assert_includes html, %(NODE_ENDPOINT="node")
    assert_includes html, %(META_ENDPOINT="node/meta")
  end

  test "inlines the type and tag indexes for client-side colour and filtering" do
    write("a.md", "---\ntype: Note\ntitle: A\ntags: [x, y]\n---\n\nz\n")

    html = render
    types = JSON.parse(html[/TYPES=(\{.*?\}), TAGS=/m, 1])
    tags = JSON.parse(html[/TAGS=(\{.*?\});/m, 1])

    assert_equal({ "Note" => [ "a" ] }, types)
    assert_equal(%w[x y], tags.keys.sort)
  end

  test "escaping neutralizes a </script> breakout in node data" do
    write("x.md", %(---\ntype: Note\ntitle: "boom </script><script>alert(1)</script>"\n---\n\nhi\n))

    assert_includes render, "\\u003c/script>"
  end

  test "omits the source link unless provided" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    refute_includes render, %(class="src")
    assert_includes render(link: "https://example.com"), "https://example.com"
  end

  private

  def render(**opts)
    graph = OKF::Bundle::Graph.build(OKF::Bundle::Reader.read(@tmpdir), minimal: true)
    OKF::Server::Graph.new(graph, **opts).render
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
