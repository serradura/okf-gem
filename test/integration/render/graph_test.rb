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

  test "the graph can draw the authored index layer, in any layout" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # the §6 map was drawable only inside file-tree mode, where a folder node
    # stood in for it; it is a layer now, and rides whatever layout is running
    assert_includes html, %(id="btn-ix"), "a toggle sits with the other graph modes"
    assert_includes html, "const IX='ix::';", "index nodes carry their own id space"
    assert_includes html, "function setIxNodes(", "and their own named action"
    assert_includes html, "getIndex().then", "built from /index — the authored layer, read where it lives"
    assert_includes html, "classes:'ixe'", "with edges of their own, so the link graph stays untouched"
    # file-tree mode's folder and the index layer's map are the same thing seen
    # twice, so one selector dresses both and they cannot drift apart
    assert_includes html, "{selector:'node.dir,node.ix',style:{'shape':'round-rectangle','background-color':cvar('--accent')",
      "a directory looks the same whichever mode drew it"
    refute_includes html, "{selector:'node.ix',style:{'background-color':cvar('--accent')",
      "with no per-mode override left to drift from it"
    assert_includes html, "{selector:'edge.tree',style:{'width':1.1,'opacity':.7,'line-style':'dashed'",
      "and an edge into a directory is dashed in both"
    assert_includes html, "'border-style':'dashed'", "an implied directory is hollow and dashed"
  end

  test "index nodes are drawn, never modelled" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # index.md is reserved: it is not a concept, and the page must not be the
    # place that quietly decides otherwise. These nodes exist on the canvas only
    nodes = JSON.parse(html[/const NODES=(\[.*?\]), EDGES=/m, 1])
    assert_empty nodes.select { |n| n["id"].to_s.include?("index") }, "no index row enters the node payload"
    assert_includes html, "cy.add({group:'nodes',classes:'ix'", "they are added to the canvas directly"
    # a type or tag filter is a statement about concepts; a map answers neither
    assert_includes html, "n.hasClass('dir')||n.hasClass('ix')", "so the filter passes them over"
    # ...but a map with nothing left to point at is the phantom empty box again
    assert_includes html, "function ixVisibility(", "an emptied map leaves the canvas with its concepts"
    assert_includes html, "btnIx.disabled=on", "and file-tree mode, which already draws folders, disables the toggle"
  end

  test "opening a map from the reader keeps the layout and turns the layer on" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # it forced file-tree mode, throwing away whatever layout the reader had
    # chosen, and dimmed the graph down to the map's immediate neighbours — the
    # reader asked to see a map *in* the graph, not to be given a different one
    assert_includes html, "function openMapInGraph(", "the action is about the map, not about tree mode"
    refute_includes html, "function openInTree(", "the tree-forcing version is gone"
    assert_includes html, "setIxNodes(true).then(", "it switches the index layer on and waits for it"
    # file-tree mode already draws folders, so there it still focuses the folder
    assert_includes html, "if(treeMode){", "and a reader already in file-tree mode stays there"
  end

  test "selecting anything emphasises it the same way" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # a concept dimmed the graph to its neighbourhood; a map did nothing at all,
    # and a folder node did nothing either. Selection has to mean one thing on
    # this canvas whatever was selected, so one function does it for all three.
    assert_includes html, "function focusNode(ele,opened){", "the emphasis is a named, shared gesture"
    assert_includes html, " focusNode(ele,opened);", "a concept delegates to it"
    assert_includes html, "if(t.hasClass('ix')){showDir(t.data('dir')||'.');return focusNode(t,true);}",
      "tapping a map emphasises it too, instead of only opening the inspector"
    assert_includes html, "if(t.hasClass('dir')){showDir(t.id().slice(DIR.length)||'.');return focusNode(t,true);}",
      "and so does tapping a folder node"
    refute_includes html, "cy.elements().removeClass('dim hl');ele.addClass('hl');",
      "no bespoke no-dim path left for maps"
  end

  test "the index layer reports when it has landed" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # the layer is fetched, so anything that wants to act on its nodes has to be
    # able to wait for them — including the case where it is already on
    assert_includes html, "if(on===ixNodes)return Promise.resolve();", "a no-op toggle still answers with a promise"
    assert_includes html, "return getIndex().then(", "and the real one hands back the fetch"
  end

  test "switching between the graph modes lands in one move" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # tearing the index layer down ran its own layout, and file-tree mode ran
    # breadthfirst a beat later — two layouts racing over the same canvas, so the
    # tree landed wrong and took another click to settle
    assert_includes html, "function setIxNodes(on,relayout){", "the teardown can be told who owns the layout"
    assert_includes html, "if(on&&ixNodes)setIxNodes(false,false);",
      "file-tree mode tears the layer down without laying out — it is about to do that itself"
    # and the add is async, so a mode change mid-flight must not land afterwards
    assert_includes html, "ixSeq=0;", "each toggle takes a ticket"
    assert_includes html, "const seq=++ixSeq;", "stamped at the moment it is asked for"
    assert_includes html, "if(seq!==ixSeq||!ixNodes||treeMode)return;",
      "a stale promise, a toggle since flipped, or tree mode all cancel the add"
  end

  test "the bundle names its own root, everywhere the root is drawn" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render(title: "minifts/.okf")

    # `(root)` and `/` are what a filesystem calls it, not what a reader does —
    # the bundle already has a name in the header, and that is the orientation
    assert_includes html, %(const BUNDLE="minifts/.okf";), "the name reaches the client, script-escaped"
    assert_includes html, "const name=dir==='.'?esc(BUNDLE):", "the tree's root row wears it"
    assert_includes html, "const label=d.dir==='.'?BUNDLE:", "so does the inspector's directory map"
    assert_includes html, "title:d?d.split('/').pop()+'/':BUNDLE", "and file-tree mode's root node"
    assert_includes html, "title:d.dir==='.'?BUNDLE:", "and the index layer's root map"
  end

  test "the area vocabulary keeps its own (root), which the CLI shares" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render(title: "Demo")

    # `(root)` is the *area* label — what `okf stats --by area` and `tags --by
    # area` print, and what their tests pin. Renaming the tree's root row must
    # not quietly rename a CLI-shared vocabulary along with it.
    assert_includes html, "const areaOf=id=>id.includes('/')?id.split('/')[0]:'(root)';",
      "an area with no directory is still (root)"
    assert_includes html, "a&&a!=='(root)'?a:'.'", "and the cluster box that names it still resolves to the root dir"
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
    assert_includes html, %(<div id="hello" hidden role="note" aria-labelledby="hello-h">),
      "a first-visit note rides at the bottom, named by its own heading"
    assert_includes html, "First time here?", "it opens by naming who it is for"
    assert_includes html, "okf-hello", "and remembers being dismissed"
    # stacked, not a wall of prose with the action buried inside it
    assert_includes html, %(<p class="hello-h" id="hello-h">), "the question is a heading, not a run-on sentence"
    assert_includes html, %(<p class="hello-hint">), "and the gestures are demoted to their own line"
    # a sibling combinator, because the note sits outside #app with the other
    # fixed overlays — the descendant form matches nothing and silently never fires
    assert_includes html, "#app:not([data-view=graph]) ~ #hello{display:none}",
      "it belongs to the graph, so it never covers another view"
    # the button says "Read the index", so it has to *open* it — switching to the
    # view alone lands on "Pick a file on the left", which is not what was promised
    assert_includes html, "function readIndex(", "the action is named for what it does"
    assert_includes html, "readIndex(){setView('files');openReserved('index','index.md');}",
      "it opens the root map, not just the panel that lists it"
    assert_includes html, "close();readIndex();", "and the note gets out of the way on the way there"
  end

  test "the first-visit note speaks touch, and does not stack on the mobile note" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # a phone is where a newcomer is least oriented, so the wording has to work
    # with a finger — and two stacked bottom banners would be worse than none
    assert_includes html, "tap any dot", "the touch wording names what a reader can actually see"
    assert_includes html, "Pinch to zoom", "with the gestures a finger has"
    assert_includes html, "click any dot", "and a pointer variant for a reader holding a mouse"
    assert_includes html, "Scroll to zoom", "whose gestures are the ones a mouse has"
    # input and chrome are independent: a touch tablet in landscape is wider than
    # 768px but still taps, and a narrow desktop window is under it but clicks
    assert_includes html, "@media (pointer:coarse)", "the verbs follow the input, not the window width"
    assert_includes html, "@media (max-width:768px){ #hello .hello-menu{display:inline} }",
      "the ☰ clause follows the width, because that is when the rail collapses"
    assert_includes html, "#hello .hello-touch{display:none}"
    assert_includes html, "#hello .hello-menu{display:none}"
    # the primary action has to be reachable with a thumb
    assert_includes html, "min-height:46px", "the button clears a touch target"
    # the canvas hint names the same gestures, so only one of them speaks at a time
    assert_includes html, "gh.style.visibility='hidden'", "the canvas hint stands down while the note is up"
    assert_includes html, "if(gh)gh.style.visibility=''", "and comes back when it is dismissed"
    refute_includes html, %(<div id="mnote" hidden role="note">), "the old mobile-only note folded into this one"
    refute_includes html, "okf-mnote", "and took its storage key with it"
  end

  test "a second beat points at the menu, only where the menu is the way through" do
    write("a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # on a compact layout the rail is behind ☰, so a reader who has just left the
    # graph has no visible way to the other views — the desktop reader can see
    # the rail and needs no telling, which is why this one is width-gated
    assert_includes html, %(<div id="hello2" hidden role="note" aria-labelledby="hello2-h">),
      "a second, lighter note exists"
    assert_includes html, "function hello2(", "shown by a named action"
    assert_includes html, "if(!matchMedia('(max-width:768px)').matches)return;",
      "and only where the rail has actually collapsed"
    assert_includes html, "okf-hello2", "with its own memory, so dismissing one is not dismissing both"
    assert_includes html, "@media (min-width:769px){ #hello2{display:none} }",
      "the stylesheet agrees, so a resize cannot strand it"
    # it fires on leaving the graph, whichever way the reader left it
    assert_includes html, "if(v!=='graph')hello2();", "any route off the graph triggers it, not just the note's button"
    assert_includes html, "menuBtn.addEventListener('click',hello2Done)",
      "opening the menu answers the note, so it stops asking"
    # ...but only a note that is actually on screen can be answered. On a compact
    # layout ☰ is the *only* way off the graph, so the first tap always precedes
    # the note — marking it done there burns the flag before it is ever seen.
    done = html[/function hello2Done\(\).*?\n\}?\n?(?=function|document)/m]
    assert_includes done.to_s, "if(h.hidden)return;",
      "a menu opened before the note was shown answers nothing"
    assert_includes done.to_s, "localStorage.setItem('okf-hello2','1')", "and one that was seen is remembered"
    # both notes are the same guide speaking, so they share a vocabulary: the
    # three node dots, and the one button treatment that clears contrast in both
    # themes. One selector styles both, so they cannot drift apart.
    second = html[/<div id="hello2".*?<\/div>\n/m]
    refute_nil second, "the second note's markup is findable"
    assert_includes second, %(<span class="hello-dots" aria-hidden="true"><i></i><i></i><i></i></span>),
      "the second note carries the same dots as the first"
    assert_includes html, "#hello #hello-go,#hello2 #hello2-x{", "and one rule dresses both buttons"
    # the dot rules are unscoped for the same reason — scoped to #hello they left
    # the second note's markup rendering at zero size, present but invisible
    assert_includes html, " .hello-dots{display:flex", "the dots are styled by class, not under one note's id"
    assert_includes html, " .hello-dots i{width:9px", "so both notes draw them at the same size"
    # per-note margin overrides are fine; a second copy of the *appearance* is not
    refute_includes html, "#hello .hello-dots{display:flex", "no id-scoped copy of the dots to drift from"
    assert_includes html, "Tap ☰ for the other views", "the heading says what to do, not what exists"
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

  test "the Indexes tab dissolves into the one tree" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # two rail items and two tabs for one section, differing only by which list
    # the column drew — the authored files belong *in* the tree, in the folder
    # they document, not on a parallel flat surface
    refute_includes html, %(id="ftab-indexes"), "the Indexes tab is gone"
    refute_includes html, %(id="ftab-files"), "and so is the tab it was paired with"
    refute_includes html, "data-ftab", "the app no longer carries a tab in its state"
    refute_includes html, "function setFtab(", "nor the function that switched it"
    refute_includes html, "function goIndexes(", "and the fake view it needed is gone"
    assert_includes html, "function activeRail(){return view;}", "a rail item is a view again, nothing more"
  end

  test "the rail keeps an Index shortcut, as an action rather than a place" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # it opens the root map, exactly as the first-visit note's button does. What
    # it is not is a view: `activeRail()` answers with the view it lands on
    # (Files), so Index never highlights and never has to pretend it is somewhere
    assert_includes html, %(data-view="index"), "the rail item is back"
    assert_includes html, "if(b.dataset.view==='index')return readIndex();", "and it runs the action, not a view switch"
    assert_includes html, "function activeRail(){return view;}", "so nothing has to fake a place for it"
    assert_includes html, "const VIEW_KEYS={'1':'graph','2':'index','3':'files','4':'catalog','5':'tags','6':'stats'};",
      "and the number keys line up with the rail again"
  end

  test "index.md and log.md render inside the folder they document" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # a directory's map belongs at the top of that directory, above the folders
    # and files it maps — that is the one place a reader looks for it
    assert_includes html, "function resIn(", "reserved rows are collected per directory"
    assert_includes html, "+resIn(dir,depth+1)\n   +(kids[dir]||[]).map",
      "and render above the subfolders and concepts of that directory"
    assert_includes html, "data-res=", "each keeps its kind, so a click still knows what it opened"
  end

  test "a toggle narrows the tree to the authored layer" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # what the Indexes tab did, as a filter over the same tree rather than a
    # second surface: same rows, fewer of them, structure intact
    assert_includes html, %(id="ftree-ixonly"), "a toggle replaces the tab"
    assert_includes html, %(aria-pressed="false"), "and reads as a toggle, not a link"
    assert_includes html, "let ixOnly=false;", "with state of its own"
    assert_includes html, "ixOnly?[]:list.filter", "pressed, the concepts drop out and the authored layer stays"
  end

  test "the reader header stays hidden until a file is open" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # the head sets `hidden` in JS, but `display:flex` outranks the UA sheet's
    # `[hidden]{display:none}` — so it rendered empty, with a graph button that
    # pointed at nothing, whenever no file was open
    assert_includes html, ".fp-head[hidden]{display:none}", "an author rule has to re-assert what hidden means"
  end

  test "Indexes only puts each map where its folder header was" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # narrowed to the authored layer, every folder owns exactly one row, so the
    # header is a line of chrome per map — the row takes its place and carries
    # the path, which is what the old flat list showed and what a reader reads
    assert_includes html, "function flatRes(", "the toggle draws a flat list, not folders of one"
    assert_includes html, "if(ixOnly){el.innerHTML=flatRes(", "and takes that path before any tree is built"
    assert_includes html, "lastFileDirs=[];syncFoldAll();",
      "with no folders on screen, the fold control has nothing to fold and says so"
  end

  test "?view=index still opens the root index, now that no such view exists" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # the deep link shipped in 1.8.0 and is in the wild; it named a place that
    # has since become an action, so it resolves to the action
    assert_includes html, "if(QV==='index')readIndex();", "the old deep link lands where it always meant to"
  end

  test "collapsing the root hands the screen back on a compact layout" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # closing the root leaves one row above a column of nothing, and on a compact
    # layout that column is stacked on top of the reader — so it folds away
    assert_includes html, "function treeMin(", "the fold is a named action the tree can reach"
    assert_includes html, "if(d==='.'&&collapsedDirs.has('.')&&matchMedia('(max-width:768px)').matches){foldedByRoot=true;treeMin(true);}",
      "closing the root on a phone or tablet collapses the list to its header"
    # ...and that has to be one gesture, not two states to dig out of: reopening
    # the list on a collapsed root would otherwise show a single row, with the
    # button just used unable to bring the tree back
    assert_includes html, "let foldedByRoot=false;", "the fold remembers why it happened"
    assert_includes html, "if(!on&&foldedByRoot){foldedByRoot=false;collapsedDirs.delete('.');refreshTree();}",
      "so reopening the list undoes the collapse that folded it"
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

  test "every file's graph button reads the same" do
    write("core/a.md", "---\ntype: Note\ntitle: A\n---\n\nx\n")

    html = render

    # it said "Explore the knowledge graph" on the root index and "Open core/ in
    # graph" on a nested one, which made a single action read as three. The
    # question is the same whatever is open — where is this in the graph? — and a
    # label is not the place to answer a different one.
    assert_includes html, "function fpGraph(go){", "the button takes a destination, not a name"
    refute_includes html, "Explore the knowledge graph", "no per-file wording left"
    refute_includes html, "'Open '+d+'/ in graph'"
    assert_includes html, %(aria-label="Open in graph" title="Open in graph"), "the one label lives in the markup"
    assert_includes html, "fpGraph(()=>goToGraph(id));", "a concept goes to its node"
    assert_includes html, "fpGraph(()=>openMapInGraph(d));", "a map goes to the layer"
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
