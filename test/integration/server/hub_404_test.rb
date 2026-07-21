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

  test "the asked path is named, as a mono chip" do
    get "/b/ghost/"

    assert_includes last_response.body, %(<span class="slug-chip">/b/ghost/</span>)
    assert_includes last_response.body, "does not match a hosted bundle"
  end

  test "a near-miss slug earns a did-you-mean carrying the bundle's own title" do
    get "/b/odrers/"

    assert_equal 404, last_response.status
    assert_includes last_response.body, %(<a href="/b/orders/">@orders</a>), "the guess is a link, not a suggestion to retype"
    assert_includes last_response.body, "Orders", "and it says which bundle it means"
    assert_includes last_response.body, "Did you mean"
  end

  test "a shared prefix is a near miss however long the tail" do
    # Truncation is the commonest way a slug is wrong — a copied URL cut short.
    # Edit distance alone scores that as far away; the prefix shortcut is what
    # makes `/b/ord/` guess @orders rather than shrug.
    get "/b/ord/"

    assert_includes last_response.body, %(<a href="/b/orders/">@orders</a>)
  end

  test "a slug that resembles nothing gets no guess rather than a wrong one" do
    get "/b/zzzzzzzzzz/"

    assert_equal 404, last_response.status
    refute_includes last_response.body, "Did you mean", "a guess nobody can use is worse than none"
    assert_includes last_response.body, "/b/orders/", "the list is still the way home"
  end

  test "the list carries every fact the manager's rows carry" do
    get "/b/ghost/"

    assert_includes last_response.body, %(<a href="/b/orders/"), "title links to the bundle"
    assert_includes last_response.body, "@orders"
    assert_includes last_response.body, "1 concept"
    # The word carries the verdict and the class only tints it, so a reader who
    # cannot see the colour loses nothing. (These one-file bundles link nowhere,
    # which the linter warns about — the fixture's own honest health.)
    assert_includes last_response.body, %(<span class="b-health warn"><span class="dot"></span>1 warning</span>)
    assert_includes last_response.body, %(<span class="dbadge">default</span>)
  end

  test "the filter box is autofocused, counts what it is filtering, and states its keys" do
    get "/b/ghost/"

    assert_includes last_response.body, %(id="q"), "the same .search component the graph page's box is"
    assert_includes last_response.body, "autofocus"
    assert_includes last_response.body, %(<span class="s-cnt" id="bar-count">2</span>),
      "the total while idle; script swaps in n/total once it filters"
    assert_includes last_response.body, "↑↓ move"
  end

  # -- which failure it is

  test "a hub with nothing registered says so, and never blames the reader's query" do
    @app = OKF::Server::Hub.new([])

    get "/b/ghost/"

    assert_equal 404, last_response.status
    assert_includes last_response.body, "No bundles are registered on this server"
    refute_includes last_response.body, "No bundle matches",
      "that sentence answers a query; there was no query, and no data either"
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
