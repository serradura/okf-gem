# frozen_string_literal: true

require "test_helper"

require "json"
require "minitest/mock"
require "rack/test"

require "okf"
require "okf/server/app"

# OKF::Server::App as a Rack app — exercised in-process with rack-test, so no
# sockets are opened. Routes serve the lean page, per-node markdown (live from
# disk), a metadata fragment, and the type/tag indexes.
class OKF::Server::AppTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @tmpdir = Dir.mktmpdir("okf-server-test")
    write("tables/orders.md", "---\ntype: Table\ntitle: Orders\ndescription: the orders table\n---\n\nThe orders body.\n")
    write("notes/n.md", %(---\ntype: Note\ntitle: N\nid: pinned\ntags: [x]\ndescription: "a <b>bold</b> claim"\n---\n\nPinned body.\n))
    @app = OKF::Server::App.new(OKF::Bundle::Folder.load(@tmpdir), title: "Demo")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "GET / serves the lean HTML page with no embedded bodies" do
    get "/"

    assert_equal 200, last_response.status
    assert_match %r{text/html}, last_response.content_type
    assert_includes last_response.body, "<!doctype html"
    nodes = JSON.parse(last_response.body[/const NODES=(\[.*?\]), EDGES=/m, 1])
    assert_equal [ %w[id title] ], nodes.map { |n| n.keys.sort }.uniq
    refute_includes last_response.body, "The orders body."
  end

  test "GET / carries the fullscreen diagram viewer, Panzoom lazy-loaded" do
    get "/"

    assert_includes last_response.body, 'id="dgv"'
    assert_includes last_response.body, "@panzoom/panzoom@4"
    refute_includes last_response.body, '<script src="https://cdn.jsdelivr.net/npm/@panzoom'
  end

  test "GET /node returns the concept's raw markdown, live from disk" do
    get "/node", id: "tables/orders"

    assert_equal 200, last_response.status
    assert_match %r{text/markdown}, last_response.content_type
    assert_equal "The orders body.", last_response.body.strip

    # editing the file changes what the endpoint serves — no restart
    write("tables/orders.md", "---\ntype: Table\ntitle: Orders\n---\n\nEdited body.\n")
    get "/node", id: "tables/orders"
    assert_equal "Edited body.", last_response.body.strip
  end

  test "GET /node resolves a frontmatter id to its file" do
    get "/node", id: "pinned"

    assert_equal 200, last_response.status
    assert_equal "Pinned body.", last_response.body.strip
  end

  test "GET /node/meta returns the description, escaping HTML" do
    get "/node/meta", id: "tables/orders"
    assert_equal 200, last_response.status
    assert_match %r{text/html}, last_response.content_type
    assert_includes last_response.body, "the orders table"

    get "/node/meta", id: "pinned"
    assert_includes last_response.body, "&lt;b&gt;"
    refute_includes last_response.body, "<b>bold</b>"
  end

  test "GET /tags and /types return the inverted indexes as JSON" do
    get "/tags"
    assert_match %r{application/json}, last_response.content_type
    assert_equal({ "x" => [ "pinned" ] }, JSON.parse(last_response.body))

    get "/types"
    assert_equal(%w[Note Table], JSON.parse(last_response.body).keys.sort)
  end

  test "an unknown id, a missing id, and a traversal attempt all 404" do
    get "/node", id: "ghost"
    assert_equal 404, last_response.status
    get "/node"
    assert_equal 404, last_response.status
    get "/node", id: "../../etc/passwd"
    assert_equal 404, last_response.status
    get "/node/meta", id: "ghost"
    assert_equal 404, last_response.status
  end

  test "GET /catalog returns rich per-concept metadata for the catalog/files/stats views" do
    get "/catalog"

    assert_equal 200, last_response.status
    assert_match %r{application/json}, last_response.content_type
    data = JSON.parse(last_response.body)
    assert_equal %w[pinned tables/orders], data["concepts"].map { |concept| concept["id"] }

    orders = data["concepts"].find { |concept| concept["id"] == "tables/orders" }
    assert_equal "Table", orders["type"]
    assert_equal "the orders table", orders["description"]
    assert_equal "tables", orders["area"]
    assert_equal "tables", orders["dir"]
    assert_equal 0, orders["links_out"]

    pinned = data["concepts"].find { |concept| concept["id"] == "pinned" }
    assert_equal %w[x], pinned["tags"]
  end

  test "an unknown path and a non-GET method 404" do
    get "/nope"
    assert_equal 404, last_response.status
    post "/"
    assert_equal 404, last_response.status
  end

  test "a concept whose file vanished after boot 404s (bodies are read live)" do
    File.delete(File.join(@tmpdir, "tables/orders.md"))

    get "/node", id: "tables/orders"
    assert_equal 404, last_response.status
  end

  test "GET /index serves the §6 map: authored bodies, synthesized listings, root first" do
    write("tables/index.md", "# Tables\n\n* [Orders](orders.md) - the orders table\n")
    @app = OKF::Server::App.new(OKF::Bundle::Folder.load(@tmpdir))

    get "/index"

    assert_equal 200, last_response.status
    dirs = JSON.parse(last_response.body)["directories"]
    assert_equal ".", dirs.first["dir"], "the bundle root leads"

    tables = dirs.find { |dir| dir["dir"] == "tables" }
    assert tables["present"]
    assert_includes tables["body"], "* [Orders](orders.md)"

    notes = dirs.find { |dir| dir["dir"] == "notes" }
    assert notes["synthesized"]
    assert_equal [ "pinned" ], notes["listing"].map { |item| item["id"] }, "listing carries the frontmatter id"
  end

  test "GET /log serves every log.md, root scope first, content read live" do
    write("log.md", "# Log\n\n## 2026-07-13\n* **Update**: seeded.\n")
    write("tables/log.md", "# Tables log\n\n## 2026-07-13\n* **Creation**: tables.\n")
    @app = OKF::Server::App.new(OKF::Bundle::Folder.load(@tmpdir))

    get "/log"
    logs = JSON.parse(last_response.body)["logs"]
    assert_equal [ "log.md", "tables/log.md" ], logs.map { |log| log["path"] }
    assert_includes logs.first["content"], "seeded"

    write("log.md", "# Log\n\n## 2026-07-14\n* **Update**: fresh entry, no restart.\n")
    get "/log"
    assert_includes JSON.parse(last_response.body)["logs"].first["content"], "fresh entry, no restart"
  end

  test "GET /log with no log files is an empty list, not an error" do
    get "/log"

    assert_equal 200, last_response.status
    assert_equal [], JSON.parse(last_response.body)["logs"]
  end

  # A server pointed at one bundle still has a bundle to search, so the palette
  # works there too. The rows are the hub's rows minus `slug` — one bundle has no
  # slug to carry, and inventing one would make a standalone server answer as if
  # it were a set.
  test "GET /search ranks concepts in the one bundle being served" do
    get "/search", q: "orders"

    assert_equal 200, last_response.status
    assert_match %r{application/json}, last_response.content_type

    body = JSON.parse(last_response.body)
    assert_equal "orders", body["query"]
    assert_equal 1, body["total"]

    row = body["results"].first
    assert_equal "tables/orders", row["id"]
    assert_equal "Orders", row["title"]
    assert_equal "Table", row["type"]
    refute row.key?("slug"), "a single-bundle server has no slug to answer with"
    assert_includes row["matched"], "title"
    assert_kind_of Numeric, row["score"]
    refute body["truncated"]
  end

  # The build is ~95% of the index engine's cost, and a server has every
  # subsequent keystroke to amortize it over — where a one-shot CLI process has
  # nothing. Rebuilding per request made every search pay the whole corpus again.
  test "the index is built once and reused across searches" do
    builds = 0
    original = OKF::Bundle::Search::Index.method(:prepare)
    OKF::Bundle::Search::Index.stub(:prepare, ->(documents) { builds += 1; original.call(documents) }) do
      get "/search", q: "orders"
      assert_equal 1, JSON.parse(last_response.body)["total"]
      get "/search", q: "pinned"
      assert_equal 1, JSON.parse(last_response.body)["total"]
      get "/search", q: "bold"
    end

    assert_equal 1, builds, "three searches must share one index, not build three"
  end

  test "GET /search with no term is an empty result, not an error" do
    get "/search"

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "", body["query"]
    assert_equal [], body["results"]
    assert_equal 0, body["total"]
  end

  # The route always answers; advertising it is the caller's call. An embedding
  # app mounts this at a path of its choosing (`mount App.new(folder) =>
  # "/knowledge"`), and the page resolves SEARCH_ENDPOINT relative to the URL the
  # reader is on — so a default that advertises "search" points at the host's
  # root, not at the mount. Whoever knows where the app is mounted is the only
  # one who can name the endpoint, which is why the default stays nil and
  # `okf server` passes it.
  test "an embedded app advertises no search endpoint by default" do
    get "/"

    assert_match(/const SEARCH_ENDPOINT=null/, last_response.body)
  end

  test "a caller that knows where it is mounted names the endpoint, and the page offers it" do
    @app = OKF::Server::App.new(OKF::Bundle::Folder.load(@tmpdir), title: "Demo", search_endpoint: "search")
    get "/"

    assert_match(/const SEARCH_ENDPOINT="search"/, last_response.body)
  end

  # The route is not gated on the advertisement: an embedder that names no
  # endpoint still gets a working one to point at once it knows its own mount.
  test "GET /search answers whether or not the page advertises it" do
    get "/search", q: "orders"

    assert_equal 200, last_response.status
    assert_equal 1, JSON.parse(last_response.body)["total"]
  end

  private

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
