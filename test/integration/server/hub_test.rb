# frozen_string_literal: true

require "test_helper"

require "json"
require "rack/test"

require "okf"
require "okf/server/hub"

# OKF::Server::Hub as a Rack app — the multi-bundle dispatcher, exercised
# in-process with rack-test (no sockets). It mounts each bundle's App under
# /b/<slug>/, redirects `/` to the default bundle, and 404s the rest.
class OKF::Server::HubTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @root = Dir.mktmpdir("okf-hub-test")
    @app = OKF::Server::Hub.new([ bundle("orders", "Orders"), bundle("notes", "Notes") ])
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "GET / redirects to the default (first) bundle" do
    get "/"

    assert_equal 302, last_response.status
    assert_equal "/b/orders/", last_response.headers["location"]
  end

  test "GET /b/<slug> (no trailing slash) 301-redirects to the trailing-slash form" do
    get "/b/orders"

    assert_equal 301, last_response.status
    assert_equal "/b/orders/", last_response.headers["location"]
  end

  test "GET /b/<slug>/ serves that bundle's page" do
    get "/b/notes/"

    assert_equal 200, last_response.status
    assert_match %r{text/html}, last_response.content_type
    assert_includes last_response.body, "<!doctype html"
  end

  test "the page carries the other bundles as switch targets (server mode)" do
    get "/b/orders/"

    siblings = JSON.parse(last_response.body[/const SIBLINGS=(\[.*?\]), SELF_SLUG=/m, 1])
    # Relative on purpose: every page lives at <prefix>/b/<slug>/, so "../notes/"
    # reaches the sibling whether the hub is at / or mounted under /kb.
    assert_equal [ { "slug" => "notes", "title" => "Notes", "path" => "../notes/", "default" => false } ], siblings
    assert_includes last_response.body, %(SELF_SLUG="orders")
  end

  test "under a mounted prefix, every emitted path carries it" do
    # The class doc promises prefix-mounting (Rails `mount ... => "/kb"`), which
    # means SCRIPT_NAME is set and PATH_INFO is already relative to it.
    get "/", {}, "SCRIPT_NAME" => "/kb"
    assert_equal 302, last_response.status
    assert_equal "/kb/b/orders/", last_response.headers["location"], "the default redirect stays inside the mount"

    get "/b/", {}, "SCRIPT_NAME" => "/kb"
    assert_includes last_response.body, %(href="/kb/b/orders/"), "the index links inside the mount"
    refute_includes last_response.body, %(href="/b/orders/"), "and never outside it"

    get "/b/orders", {}, "SCRIPT_NAME" => "/kb"
    assert_equal 301, last_response.status
    assert_equal "/kb/b/orders/", last_response.headers["location"], "the trailing-slash redirect keeps the prefix"

    get "/b/ghost/", {}, "SCRIPT_NAME" => "/kb"
    assert_equal 404, last_response.status
    assert_includes last_response.body, %(href="/kb/b/orders/"), "the 404's way home stays inside the mount"
  end

  test "GET /b/ serves a self-contained bundle index with the default marked" do
    get "/b/"

    assert_equal 200, last_response.status
    assert_match %r{text/html}, last_response.content_type
    assert_includes last_response.body, "/b/orders/"
    assert_includes last_response.body, "/b/notes/"
    assert_includes last_response.body, %(<span class="def">default</span>)
    refute_includes last_response.body, "http://", "the index makes no external requests"

    get "/b"
    assert_equal 200, last_response.status, "the no-slash form serves the same index"
  end

  test "redirects preserve the query string" do
    get "/b/orders?view=files&select=a"
    assert_equal 301, last_response.status
    assert_equal "/b/orders/?view=files&select=a", last_response.headers["location"]

    get "/?view=index"
    assert_equal 302, last_response.status
    assert_equal "/b/orders/?view=index", last_response.headers["location"]
  end

  test "an unknown slug 404s as a page listing the hosted bundles" do
    get "/b/ghost/"

    assert_equal 404, last_response.status
    assert_match %r{text/html}, last_response.content_type
    assert_includes last_response.body, "/b/ghost/"
    assert_includes last_response.body, "/b/orders/", "the 404 offers a way home"
  end

  test "a bundle's own relative endpoints resolve under its mount prefix" do
    get "/b/orders/node", id: "a"

    assert_equal 200, last_response.status
    assert_equal "hi", last_response.body.strip

    get "/b/notes/catalog"
    assert_equal 200, last_response.status
    assert_match %r{application/json}, last_response.content_type
  end

  test "an unknown slug and a non-GET method 404" do
    get "/b/ghost/"
    assert_equal 404, last_response.status

    get "/elsewhere"
    assert_equal 404, last_response.status

    post "/b/orders/"
    assert_equal 404, last_response.status
  end

  test "default_slug picks the / redirect target" do
    @app = OKF::Server::Hub.new([ bundle("a1", "A"), bundle("b1", "B") ], default_slug: "b1")

    get "/"
    assert_equal "/b/b1/", last_response.headers["location"]
  end

  test "an unknown default_slug falls back to the first bundle" do
    @app = OKF::Server::Hub.new([ bundle("a2", "A"), bundle("b2", "B") ], default_slug: "ghost")

    get "/"
    assert_equal "/b/a2/", last_response.headers["location"]
  end

  test "with a single bundle, / still redirects to it" do
    @app = OKF::Server::Hub.new([ bundle("only", "Only") ])

    get "/"
    assert_equal 302, last_response.status
    assert_equal "/b/only/", last_response.headers["location"]
  end

  test "an empty hub serves a self-contained landing page, not a redirect" do
    @app = OKF::Server::Hub.new([])

    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "No bundles registered"
    refute_includes last_response.body, "http://", "the landing makes no external requests"
  end

  private

  def bundle(slug, title)
    dir = File.join(@root, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.md"), "---\ntype: Note\ntitle: A\ndescription: d\n---\n\nhi\n")
    OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(dir), title)
  end
end
