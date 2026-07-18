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

  test "empowers the search box with a MiniSearch full-text index over descriptions and bodies" do
    write("a.md", "---\ntype: Note\ntitle: A\ndescription: the alpha note\n---\n\nx\n")

    html = render

    assert_includes html, "minisearch@7.2.0/dist/umd/index.js",
      "loads the version-pinned MiniSearch build — bit-for-bit with the Ruby port"
    assert_includes html, "new MiniSearch(", "builds a client-side full-text index"
    assert_match(/FT_FIELDS=\[ ?'title','id','type','tags','description'/, html,
      "descriptions are indexed, so a graph node is findable by its leaf description")
    assert_includes html, "EMBED?[ 'body' ]".delete(" "),
      "concept bodies join the index wherever the page holds them (the static bake)"
  end

  test "hides a cluster box once a filter empties it, and binds Esc to deselect" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # an area box whose children are all filtered out drops out of the drawing,
    # not just out of the fit — so a search never leaves phantom empty boxes
    assert_includes html, "cy.nodes(':parent').forEach(p=>p.style('display'",
      "the graph filter recomputes each compound parent's visibility from its children"
    # a dense graph has no empty canvas to click, so Esc clears the selection
    assert_includes html, "function deselect(", "deselect is a named, reusable action"
    assert_includes html, "e.key==='Escape'&&view==='graph'", "Esc clears the graph selection"
  end

  test "the files panel searches index/log bodies, folds during search, and folds all" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # the Indexes tab searches reserved-file bodies through its own MiniSearch index
    assert_includes html, "function buildFtResIndex(",
      "the Indexes tab has a full-text index over index.md/log.md bodies"
    assert_includes html, "if(d.present)docs.push({id:'idx:'+d.index_path",
      "index.md bodies are indexed, not just their paths"
    # collapse must work even while a search/filter is active (was force-expanded)
    assert_includes html, "const closed=collapsedDirs.has(dir);",
      "folders honor their collapsed state regardless of an active search"
    refute_includes html, "!filtering&&collapsedDirs", "the search-forces-expand override is gone"
    # one control folds/unfolds every visible group
    assert_includes html, %(id="ftree-foldall"), "a fold/unfold-all control exists"
    assert_includes html, "foldAllBtn.onclick", "the fold-all control is wired"
  end

  test "the page opens on the graph, and a first visit is told the index exists" do
    write("index.md", "---\nokf_version: \"0.1\"\ntitle: Handbook\n---\n\n# Handbook\n")
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # the graph is the first impression and stays that way; landing on the index
    # instead only read well on a wide window, and cost every visitor the view
    # that makes the bundle legible at a glance
    assert_includes html, %(<div id="app" data-view="graph">), "the page boots on the graph"
    assert_includes html, "let view='graph';"
    assert_includes html, %(<button class="rail-item active" data-view="graph">), "the rail stands on Graph"
    assert_includes html, %(<section class="view active" id="view-graph">), "and the graph section is the one revealed"
    refute_includes html, "function landOnIndex(", "the index landing is gone"
    # what carries the index instead: one dismissible note, once, on every width
    assert_includes html, %(<div id="hello" hidden role="note">), "a first-visit note rides at the bottom"
    assert_includes html, "First time here?", "it opens by naming who it is for"
    assert_includes html, "okf-hello", "and remembers being dismissed"
    # a sibling combinator, because the note sits outside #app with the other
    # fixed overlays — the descendant form matches nothing and silently never fires
    assert_includes html, "#app:not([data-view=graph]) ~ #hello{display:none}",
      "it belongs to the graph, so it never covers another view"
    assert_includes html, "hello-go", "one tap goes straight to the index"
  end

  test "the first-visit note speaks touch, and does not stack on the mobile note" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # a phone is where a newcomer is least oriented, so the wording has to work
    # with a finger — and two stacked bottom banners would be worse than none
    assert_includes html, "tap a concept to read it", "the graph hint is written for touch, not for a mouse"
    assert_includes html, "pinch to zoom", "and the touch-only half carries the gestures a phone needs"
    refute_includes html, "click a concept to read", "no mouse-only wording in the note"
    refute_includes html, %(<div id="mnote" hidden role="note">), "the old mobile-only note folded into this one"
    refute_includes html, "okf-mnote", "and took its storage key with it"
  end

  test "a concept deep link carries the view with it" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # ?select= and #hash name a *node*, so they say which view to name it in
    # rather than trusting whichever one the page happens to be standing on
    assert_includes html, "if(QS&&byId[QS])goToGraph(QS);", "?select= switches to the graph before selecting"
    assert_includes html, "if(h&&byId[h])goToGraph(h);", "so does a #hash"
  end

  test "the file tree nests directories instead of listing full paths flat" do
    write("core/configurations/deep.md", "---\ntype: Note\ntitle: Deep\n---\n\nx\n")
    write("core/mid.md", "---\ntype: Note\ntitle: Mid\n---\n\nx\n")
    write("top.md", "---\ntype: Note\ntitle: Top\n---\n\nx\n")

    html = render

    # `core` and `core/configurations` were siblings in a sorted flat list, which
    # reads as two unrelated folders rather than a parent and its child
    assert_includes html, "function subtree(", "the tree renders recursively from path segments"
    refute_includes html, "const dirs=Object.keys(groups).sort();", "the flat full-path grouping is gone"
    assert_includes html, "style=\"--d:", "each row carries its depth, so the tree indents"
    assert_includes html, "const closed=collapsedDirs.has(dir);", "folders still honor their collapsed state"
    assert_includes html, "calc(8px + var(--d,0)", "and the depth reaches the stylesheet as indentation"
    # a folder holding only folders still has to appear, or the chain breaks
    assert_includes html, "function dirParents(", "every ancestor joins the tree even when it holds no files"
  end

  test "collapse-all folds into the root, not over it" do
    write("core/configurations/deep.md", "---\ntype: Note\ntitle: Deep\n---\n\nx\n")
    write("cli/render.md", "---\ntype: Note\ntitle: Render\n---\n\nx\n")

    html = render

    # folding the root too answers "collapse all" with a lone (root) row, hiding
    # the top-level folders — the one thing the control exists to reveal
    assert_includes html, "function foldable(", "the root is not among the folders the control folds"
    assert_includes html, "collapsedDirs.delete('.')", "collapse-all leaves the root open"
    assert_includes html, "collapsedDirs.clear()", "expand-all reopens everything, including a root closed by hand"
    refute_includes html, "d.forEach(x=>collapsedDirs.delete(x))", "the old all-inclusive fold is gone"
  end

  test "the reader's graph button says what it will open" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # on the root index it opens the whole bundle, on a nested one just that
    # folder — and saying so is the invitation a first-time reader needs, put
    # where their eye already is instead of in a banner they have to dismiss
    assert_includes html, "function fpGraph(", "one place relabels and rewires the button"
    assert_includes html, "'Explore the knowledge graph'", "the root index opens the whole graph"
    assert_includes html, "'Open '+d+'/ in graph'", "a nested index names its own folder"
    assert_includes html, "fpGraph('Open in graph',()=>goToGraph(id));",
      "a concept resets the label, so a stale one never outlives the index that set it"
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
