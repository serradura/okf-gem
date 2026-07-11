# frozen_string_literal: true

require "test_helper"

require "json"
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

  private

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end
