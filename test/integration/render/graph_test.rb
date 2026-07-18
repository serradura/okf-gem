# frozen_string_literal: true

require "test_helper"

require "json"

require "okf"
require "okf/render/graph"

class OKF::Render::GraphTest < OKF::TestCase
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

  test "loads cytoscape, marked and DOMPurify and wires the on-demand endpoints" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    assert_includes html, "cytoscape"
    assert_includes html, "marked"
    assert_includes html, "dompurify", "DOMPurify sanitizes each fetched body before render"
    assert_includes html, "DOMPurify.sanitize(marked.parse(text))", "the body render passes through the sanitizer"
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

  test "server mode injects EMBED=null so the getters fetch live" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\n" + ("x" * 5000))

    html = render

    assert_includes html, "const EMBED=null;"
    refute_includes html, "x" * 5000, "server mode embeds no body"
  end

  test "render mode bakes the payload into EMBED and keeps the sanitizer on the path" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nz\n")
    payload = { catalog: [], index: [], logs: [], bodies: { "a" => "BAKEDBODYMARK" } }

    html = render(embed: payload)

    assert_includes html, "const EMBED={"
    refute_includes html, "const EMBED=null;"
    assert_includes html, "BAKEDBODYMARK", "the body is embedded for offline render"
    assert_includes html, "DOMPurify.sanitize(marked.parse(text))", "embedded bodies still route through the sanitizer"
  end

  test "escaping neutralizes a </script> breakout inside an embedded body" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nz\n")
    payload = { catalog: [], index: [], logs: [], bodies: { "a" => "x</script><script>alert(1)</script>" } }

    html = render(embed: payload)

    assert_includes html, "\\u003c/script>"
    refute_includes html, "</script><script>alert(1)", "the raw breakout never reaches the page"
  end

  test ".static renders a whole bundle from a folder — bundle baked in, meta derived from the catalog" do
    write("tables/orders.md", "---\ntype: Table\ntitle: Orders\ndescription: the orders table\n---\n\nThe orders body.\n")
    write("notes/n.md", %(---\ntype: Note\ntitle: N\ndescription: "a <b>bold</b> claim"\n---\n\nPinned body.\n))

    html = OKF::Render::Graph.static(OKF::Bundle::Folder.load(@tmpdir), title: "Demo")

    assert_includes html, "<!doctype html"
    assert_includes html, "const EMBED={"
    refute_includes html, "const EMBED=null;"
    assert_includes html, "The orders body.", "bodies the live server would fetch are baked in"
    assert_includes html, %("bodies":)
    assert_includes html, %("catalog":)
    refute_includes html, %("meta":), "meta is no longer a baked key — derived on the client from the catalog"
    assert_includes html, "a \\u003cb>bold\\u003c/b> claim", "the raw description rides in the catalog, script-escaped"
    refute_includes html, "a &lt;b&gt;bold&lt;/b&gt; claim", "the pre-escaped fragment is not baked"
  end

  private

  def render(**opts)
    graph = OKF::Bundle::Graph.build(OKF::Bundle::Reader.read(@tmpdir), minimal: true)
    OKF::Render::Graph.new(graph, **opts).render
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
