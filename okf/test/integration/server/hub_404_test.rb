# frozen_string_literal: true

require "test_helper"

require "rack/test"

require "okf"
require "okf/server/hub"

# The hub's 404 — the page a stale bookmark lands on after a rename, and the
# only page in the product a reader reaches by being wrong. It is not a design
# of its own: it is the app shell with nothing to show, so it wears the same
# rail, the same topbar, the same search component and the same row anatomy the
# graph page uses, and only the main column differs.
#
# Everything a reader needs is server-rendered — the asked path, the guess, the
# list — because this is where a reader lands when something has already gone
# wrong, and a page that needs JavaScript to say what happened has picked the
# worst possible moment to need it. Script adds the live filter and the
# keyboard, and nothing else.
class OKF::Server::Hub404Test < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @root = Dir.mktmpdir("okf-hub-404-test")
    @app = OKF::Server::Hub.new([ bundle("orders", "Orders"), bundle("notes", "Notes") ])
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  # -- the app shell, not a chrome of its own

  test "the 404 is built on the app shell: the rail, the mark, the theme toggle, the topbar" do
    get "/b/ghost/"

    assert_equal 404, last_response.status
    assert_includes last_response.body, %(<div id="app">), "the same two-column shell every view lives in"
    assert_includes last_response.body, %(<nav id="rail"), "the 76px rail, not a slim bar invented here"
    assert_includes last_response.body, %(<header id="topbar">)
    assert_includes last_response.body, %(id="btn-theme"), "the theme toggle the rail carries everywhere else"
    assert_includes last_response.body, "<svg viewBox=\"0 0 100 100\">", "the ruby mark"
  end

  test "the mark is the way home, in the rail and in the folded bar alike" do
    get "/b/ghost/"

    assert_equal 2, last_response.body.scan(%r{href="/b/" title="All bundles"}).length,
      "the rail's mark and the ≤768px bar's mark both lead to the bundle list"
  end

  test "≤768px folds the rail away and moves the mark into the bar" do
    get "/b/ghost/"

    assert_match(/@media \(max-width:768px\)\{.*?#rail\{display:none\}/m, last_response.body)
    assert_includes last_response.body, ".bar-brand{display:none", "hidden until the rail folds"
  end

  # -- what it says

  test "the asked path is the heading, and the verdict is the small word above it" do
    # The sizes are swapped on purpose. A reader arrives already knowing they
    # are lost — the URL bar said so — so the diagnosis is the eyebrow and what
    # they actually asked for is the display line, set in mono where a dropped
    # slash or a truncated slug reads as a shape.
    get "/b/ghost/"

    assert_includes last_response.body, %(<h1>/b/ghost/</h1>)
    assert_includes last_response.body, %(<p class="eyebrow">Not found</p>)
    assert_includes last_response.body, "Bundles are served at", "and it teaches the shape of a URL that works"
  end

  test "a near-miss slug earns a did-you-mean carrying the bundle's own title" do
    get "/b/odrers/"

    assert_equal 404, last_response.status
    assert_includes last_response.body, "Closest match"
    # The guess is the same row anatomy as the list below it, so what a reader
    # learns to read in one place reads the same in the other — and ⏎ is already
    # pointed at it, which a sentence in muted grey never was.
    assert_match(%r{<div class="miss">.*?<a href="/b/orders/" class="active">.*?Orders}m, last_response.body)
  end

  test "a shared prefix is a near miss however long the tail" do
    # Truncation is the commonest way a slug is wrong — a copied URL cut short.
    # Edit distance alone scores that as far away; the prefix shortcut is what
    # makes `/b/ord/` guess @orders rather than shrug.
    get "/b/ord/"

    assert_match(%r{<div class="miss">.*?href="/b/orders/"}m, last_response.body)
  end

  test "a path that dropped the mount separator still finds the bundle inside it" do
    # /bnotes/ is /b/notes/ with one slash missing, which is the likeliest way a
    # hand-typed URL comes out wrong when every bundle lives at /b/<name>/. The
    # splitter sees nothing under the mount and hands back no slug at all, so a
    # guess that only ever looks at the slug is silent on the commonest typo
    # there is — and this page's whole job is the guess.
    get "/bnotes/"

    assert_equal 404, last_response.status
    assert_match(%r{<div class="miss">.*?href="/b/notes/"}m, last_response.body)
    assert_includes last_response.body, "with the slash after", "and it names what actually went wrong"
  end

  test "a bundle really named for the mount letter beats the same name without it" do
    # The other side of the fallback. /borders/ must not resolve to @orders by
    # eating the `b` when a bundle called @borders is right there — the whole
    # segment is read first, and a dropped slash is claimed only on evidence
    # that leaves no second reading.
    @app = OKF::Server::Hub.new([ bundle("borders", "Borders"), bundle("orders", "Orders") ])

    get "/borders/"

    assert_match(%r{<div class="miss">.*?href="/b/borders/"}m, last_response.body)
    refute_includes last_response.body, "with the slash after"
    assert_includes last_response.body, "the <code>/b/</code> is missing",
      "the mistake is a missing prefix, not a moved slash, and it says which"
  end

  test "a slug that resembles nothing gets no guess rather than a wrong one" do
    get "/b/zzzzzzzzzz/"

    assert_equal 404, last_response.status
    refute_includes last_response.body, "Did you mean", "a guess nobody can use is worse than none"
    assert_includes last_response.body, "/b/orders/", "the list is still the way home"
  end

  test "the list carries every fact the /b/ rows carry, the folder included" do
    get "/b/ghost/"

    assert_includes last_response.body, %(<a href="/b/orders/"), "title links to the bundle"
    assert_includes last_response.body, "@orders"
    assert_includes last_response.body, "1 concept"
    # The folder is the fact the old row dropped, and the one that matters most
    # on a real server: a hub hosting site/.okf, minifts/.okf and okf-core/.okf
    # has three titles that read almost alike, and the directory is all that
    # tells them apart.
    assert_match(%r{<span class="b-dir" title="[^"]*orders"><bdi>[^<]*orders</bdi></span>}, last_response.body)
    # The verdict rides on the row, so the word and the 3px edge come from one
    # source. (These one-file bundles link nowhere, which the linter warns
    # about — the fixture's own honest health.)
    assert_includes last_response.body, %(<li class="brow" data-health="warn")
    assert_includes last_response.body, %(<span class="b-health">1 warning</span>)
    assert_includes last_response.body, %(<span class="dbadge">default</span>)
  end

  test "the filter box is the graph page's own, count, bridge and all" do
    get "/b/ghost/"

    assert_includes last_response.body, %(id="q"), "the same .search component the graph page's box is"
    assert_includes last_response.body, "autofocus"
    assert_includes last_response.body, %(<span class="s-cnt" id="bar-count">2</span>),
      "the total while idle; script swaps in n/total once it filters"
    # The dead end is the same event here as on the graph page — the box came up
    # empty and there is somewhere else to look — so it is the same component in
    # the same place, rather than a second dialect of one idea two pages apart.
    assert_includes last_response.body, %(<div id="s-bridge" class="s-bridge" role="status" hidden>)
    assert_includes last_response.body, %(id="sb-go">Search every bundle <kbd>⏎</kbd>)
    assert_includes last_response.body, %(id="sb-clear">Clear <kbd>esc</kbd>)
    # No key hints under the list: Tab moves through it natively, and a page
    # that has to teach Tab has invented something it did not need to.
    refute_includes last_response.body, "move ·"
  end

  # -- which failure it is

  test "a hub with nothing registered says so, and never blames the reader's query" do
    @app = OKF::Server::Hub.new([])

    get "/b/ghost/"

    assert_equal 404, last_response.status
    assert_includes last_response.body, "No bundles are registered on this server"
    # The markup, not the bare word: the stylesheet is inlined on every one of
    # these pages, so asserting the token would only ever prove the CSS exists.
    refute_includes last_response.body, %(id="s-bridge"),
      "the bridge answers a query; there was no query, and nothing to filter either"
    refute_includes last_response.body, %(id="q"), "and nothing to filter is nothing to offer a filter for"
  end

  # -- escaping

  test "an asked path of markup is inert, wherever it lands" do
    # PATH_INFO is set directly because that is what the app really receives:
    # a browser percent-encodes, WEBrick decodes, and the handler is handed the
    # raw string. rack-test skips the decode, so a plain `get` would prove only
    # that percent-encoding is inert — which was never in doubt.
    probe = "<img src=x onerror=alert(1)>"

    get "/b/x/", {}, "PATH_INFO" => "/b/#{probe}/"

    assert_equal 404, last_response.status
    refute_includes last_response.body, probe, "never as markup"
    refute_includes last_response.body, "<img", "no tag survives, however the rest of the string reads"
    assert_includes last_response.body, "&lt;img src=x onerror=alert(1)&gt;", "as text, which is what it is"
  end

  test "a bundle whose title is markup is inert in the list and in the guess" do
    @app = OKF::Server::Hub.new([ bundle("orders", %(<script>alert(1)</script>)) ])

    get "/b/odrers/"

    refute_includes last_response.body, "<script>alert(1)</script>"
    assert_includes last_response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  # -- and it stays self-contained

  test "the 404 makes no external request" do
    get "/b/ghost/"

    refute_includes last_response.body, "http://"
    refute_includes last_response.body, "https://"
  end

  private

  def bundle(slug, title)
    dir = File.join(@root, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.md"), "---\ntype: Note\ntitle: A\ndescription: d\n---\n\nhi\n")
    OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(dir), title)
  end
end
