# frozen_string_literal: true

require "test_helper"

require "json"
require "rack/test"

require "okf"
require "okf/registry"
require "okf/server/hub"

# The server's only state-changing requests: default / rename / remove / add,
# POSTed by the graph page's Bundles panel and answered as data. Three things
# have to hold on every one of them, and each has cost somebody a bad afternoon
# somewhere:
#
#   * the registry file on disk actually changed;
#   * the *live* hub reflects it without a restart — a write that leaves the
#     running server serving the old set is a lie the next click believes;
#   * a request that should not have been honoured is not honoured, and says
#     why in a sentence the person reading it can act on.
class OKF::Server::HubWritesTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @root = Dir.mktmpdir("okf-hub-writes-test")
    @home = File.join(@root, "home")
    FileUtils.mkdir_p(@home)
    boot("alpha", "beta")
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  # ── the four verbs ────────────────────────────────────────────────────────

  test "default moves the entry to the front, on disk and in the live hub" do
    post_write("/registry/default", slug: "beta")

    assert_equal 200, last_response.status
    assert_equal true, json_body["ok"]
    assert_equal %w[beta alpha], reloaded.slugs, "the file is the record"

    get "/"
    assert_equal "/b/beta/", last_response.headers["location"], "and the running hub opens the new default"
  end

  test "rename gives the entry a new slug and a new mount" do
    post_write("/registry/rename", slug: "alpha", to: "handbook")

    assert_equal 200, last_response.status
    assert_includes reloaded.slugs, "handbook"

    get "/b/handbook/"
    assert_equal 200, last_response.status, "the new mount answers without a restart"

    get "/b/alpha/"
    assert_equal 404, last_response.status, "and the old one stops answering"
  end

  test "remove drops the entry and leaves the directory alone" do
    dir = File.join(@root, "beta")

    post_write("/registry/remove", slug: "beta")

    assert_equal 200, last_response.status
    assert_equal %w[alpha], reloaded.slugs
    assert File.directory?(dir), "removing a reference never deletes the bundle"

    get "/b/beta/"
    assert_equal 404, last_response.status
  end

  test "add registers a directory by path and mounts it live" do
    make_bundle("gamma")

    post_write("/registry/add", path: File.join(@root, "gamma"))

    assert_equal 200, last_response.status
    assert_includes reloaded.slugs, "gamma"

    get "/b/gamma/"
    assert_equal 200, last_response.status
  end

  test "add takes an explicit slug and can claim the default in one step" do
    make_bundle("gamma")

    post_write("/registry/add", path: File.join(@root, "gamma"), as: "notes", default: "1")

    assert_equal %w[notes alpha beta], reloaded.slugs
    get "/"
    assert_equal "/b/notes/", last_response.headers["location"]
  end

  # ── the refusals ──────────────────────────────────────────────────────────

  test "a path that is not a directory is refused with a sentence, not a stack" do
    post_write("/registry/add", path: File.join(@root, "nowhere"))

    assert_equal 400, last_response.status
    assert_includes last_response.body, "not a directory"
    assert_equal %w[alpha beta], reloaded.slugs, "and nothing was written"
  end

  test "a directory carrying no concepts is refused before it is registered" do
    FileUtils.mkdir_p(File.join(@root, "empty"))

    post_write("/registry/add", path: File.join(@root, "empty"))

    assert_equal 400, last_response.status
    assert_includes last_response.body, "no concepts"
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a reserved slug is refused with the core's own message" do
    post_write("/registry/rename", slug: "alpha", to: "all")

    assert_equal 400, last_response.status
    assert_includes last_response.body, "all"
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a slug already in use is refused" do
    post_write("/registry/rename", slug: "alpha", to: "beta")

    assert_equal 400, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a slug no entry carries is refused" do
    post_write("/registry/remove", slug: "ghost")

    assert_equal 400, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a missing field is a refusal, not a nil sailing into the core" do
    post_write("/registry/rename", slug: "alpha")

    assert_equal 400, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "an unknown registry route 404s" do
    post_write("/registry/nuke", slug: "alpha")

    assert_equal 404, last_response.status
  end

  # ── the gates ─────────────────────────────────────────────────────────────

  test "without the CSRF token the write is refused" do
    post "/registry/remove", { slug: "beta" }, csrf_env

    assert_equal 403, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a token from somewhere else is refused" do
    post "/registry/remove", { slug: "beta", token: "not-the-token" }, csrf_env

    assert_equal 403, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a cross-origin post is refused even carrying the token" do
    # The token is in the page, and a page is a thing another site can get a
    # reader to submit. Origin is the second lock, not a redundant one.
    post "/registry/remove", { slug: "beta", token: token }, "HTTP_ORIGIN" => "http://evil.test"

    assert_equal 403, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a read-only hub refuses every write, and says so where the panel reads" do
    boot("alpha", "beta", writable: false)

    # /b/ carries no controls either way now, so the honest signal is the one
    # the Bundles panel actually reads before it decides what to offer.
    get "/bundles"
    assert_equal false, JSON.parse(last_response.body)["writable"]

    post_write("/registry/remove", slug: "beta")
    assert_equal 403, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  # A read-only hub is what a public deployment binds, so "refuses writes" has to
  # mean *every* write, not the one a test happened to pick. Each verb is posted
  # with everything a legitimate caller would carry — same origin, this boot's
  # token, valid arguments — and the registry file is compared byte for byte
  # afterwards, because a 403 that still wrote is the failure this guards.
  test "a read-only hub refuses all four verbs, and the file on disk never moves" do
    make_bundle("gamma")
    boot("alpha", "beta", writable: false)
    before = File.read(OKF::Registry.load(home: @home).path)

    writes = [
      [ "/registry/default", { slug: "beta" } ],
      [ "/registry/rename", { slug: "alpha", to: "handbook" } ],
      [ "/registry/remove", { slug: "beta" } ],
      [ "/registry/add", { path: File.join(@root, "gamma") } ]
    ]
    writes.each do |path, params|
      post_write(path, params)
      assert_equal 403, last_response.status, "#{path} answered #{last_response.status}"
      assert_equal false, json_body["ok"]
    end

    assert_equal before, File.read(OKF::Registry.load(home: @home).path), "not one byte reached the registry"
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a read-only hub is refused before the token is even considered" do
    # Gate order is the security property, not an implementation detail: a
    # read-only server must not become writable to whoever can produce a token,
    # and must not leak whether a token was right by answering differently.
    boot("alpha", "beta", writable: false)

    post "/registry/remove", { slug: "beta", token: token }, csrf_env
    with_token = last_response.status
    post "/registry/remove", { slug: "beta", token: "not-the-token" }, csrf_env

    assert_equal 403, with_token
    assert_equal with_token, last_response.status, "a wrong token and a right one get the same answer"
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a read-only hub bakes no token into the page a scraper would read" do
    # The panel's credential is baked into the graph page as MANAGE_TOKEN. On a
    # read-only hub it is null — so a page pulled off a public deployment holds
    # nothing to replay, and the gate above is not the only thing standing there.
    boot("alpha", "beta", writable: false)

    get "/b/alpha/"

    assert_includes last_response.body, "MANAGE_TOKEN=null"
    refute_includes last_response.body, @app.send(:token), "the page carries no credential it cannot use"
  end

  test "no route on the whole server answers a non-GET but /registry/*" do
    # The blast radius, stated as a test. If a write surface is ever added to a
    # bundle's own App, this fails and whoever added it has to come and say so
    # here — which is the point, because a public deployment's guarantee is
    # "nothing writes", not "the registry does not write".
    boot("alpha", "beta", writable: false)

    [ "/", "/b/", "/b/alpha/", "/b/alpha/node?id=a", "/bundles", "/search?q=a" ].each do |path|
      post path, {}, csrf_env
      assert_equal 404, last_response.status, "POST #{path} answered #{last_response.status}"
    end
  end

  test "an ephemeral hub has no registry to write to" do
    @app = OKF::Server::Hub.new([ hosted("alpha") ], writable: true)

    post "/registry/remove", { slug: "alpha", token: "any" }, csrf_env
    assert_equal 409, last_response.status
  end

  # ── the shape the panel reads ─────────────────────────────────────────────
  #
  # The panel stays where it is and re-reads the list, so a write answers with
  # the outcome rather than a page. That used to be one of two renderings, the
  # other being the redirect /b/'s forms wanted; with the forms gone it is the
  # only one, and Accept decides nothing.

  test "a write answers with the outcome, not a redirect" do
    post_write("/registry/default", slug: "beta", accept: :json)

    assert_equal 200, last_response.status, "no redirect: the panel never left the page it is on"
    assert_match %r{application/json}, last_response.content_type
    assert_equal true, json_body["ok"]
    assert_includes json_body["message"], "@beta", "the same sentence the manager would have flashed"
    assert_equal %w[beta alpha], reloaded.slugs, "and the file is still the record"
  end

  test "a JSON write that is refused says why, at the same status the form gets" do
    boot("alpha", "beta", writable: false)

    post_write("/registry/remove", slug: "beta", accept: :json)

    assert_equal 403, last_response.status, "the guard is the guard; only the rendering changed"
    assert_equal false, json_body["ok"]
    assert_includes json_body["error"], "--read-only"
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a core refusal reaches the panel as JSON, carrying the core's own sentence" do
    # A collision, not a malformed slug: the core *normalizes* what it is given,
    # so "Not A Slug" would quietly become @not-a-slug and succeed.
    post_write("/registry/rename", slug: "alpha", to: "beta", accept: :json)

    assert_equal 400, last_response.status
    assert_equal false, json_body["ok"]
    refute_empty json_body["error"].to_s, "a refusal nobody can read is a refusal that teaches nothing"
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "a JSON write still needs the token and the origin" do
    post "/registry/remove", { slug: "beta" }, csrf_env.merge("HTTP_ACCEPT" => "application/json")

    assert_equal 403, last_response.status
    assert_equal false, json_body["ok"]
    assert_equal %w[alpha beta], reloaded.slugs, "asking for JSON is not a way around the locks"
  end

  # ── the page the forms used to live on ────────────────────────────────────
  #
  # /b/ managed the registry with plain forms, and the Bundles panel then did
  # the same four verbs from the graph page. Two implementations of one contract
  # is the thing that drifts, so the forms are gone and the routes stayed: /b/ is
  # the list, the landing and the empty state, and management happens where the
  # reader already is.

  test "the manager carries no forms, and no token to put in one" do
    get "/b/"

    refute_includes last_response.body, "<form"
    refute_includes last_response.body, "registry/"
    refute_includes last_response.body, token,
      "a page with nothing to post has no business holding the credential"
  end

  test "the rows are still there, and still link into their bundles" do
    get "/b/"

    assert_includes last_response.body, %(href="/b/alpha/")
    assert_includes last_response.body, %(href="/b/beta/")
  end

  test "a write answers as data whatever the caller said it wanted" do
    # The redirect existed for a form that no longer exists. There is one caller
    # now and it is a fetch(), so there is one rendering — asking for HTML does
    # not resurrect a page-shaped answer that nothing would read.
    post "/registry/rename", { slug: "alpha", to: "handbook", token: token },
      csrf_env.merge("HTTP_ACCEPT" => "text/html")

    assert_equal 200, last_response.status
    assert_equal "application/json; charset=utf-8", last_response.headers["content-type"]
    assert_equal true, json_body["ok"]
    assert_equal %w[beta handbook], reloaded.slugs.sort
  end

  test "a refusal is data too, rather than a page carrying the reason" do
    post "/registry/rename", { slug: "alpha", to: "beta", token: token },
      csrf_env.merge("HTTP_ACCEPT" => "text/html")

    assert_equal 400, last_response.status
    assert_equal false, json_body["ok"]
    refute_includes last_response.body, "<html"
  end

  test "a write under a mounted prefix is answered inside it" do
    post "/registry/rename", { slug: "alpha", to: "handbook", token: token },
      csrf_env.merge("SCRIPT_NAME" => "/kb")

    assert_equal 200, last_response.status
    assert_equal true, json_body["ok"]
  end

  private

  def boot(*slugs, writable: true)
    registry = OKF::Registry.load(home: @home)
    slugs.each { |slug| registry.add(make_bundle(slug), as: slug) }
    @app = OKF::Server::Hub.new(
      slugs.map { |slug| hosted(slug) },
      registry: OKF::Registry.load(home: @home),
      writable: writable
    )
  end

  def hosted(slug)
    OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(File.join(@root, slug)), slug.capitalize)
  end

  def make_bundle(slug)
    dir = File.join(@root, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.md"), "---\ntype: Note\ntitle: A\n---\n\nA concept.\n")
    dir
  end

  def reloaded
    OKF::Registry.load(home: @home)
  end

  # This boot's token. It used to be scraped off /b/, which is exactly what a
  # browser did with the forms there; now the only page that carries it is the
  # graph page (baked as MANAGE_TOKEN), so the test asks the hub directly rather
  # than reaching through a second app to read a value this one owns.
  def token
    @app.send(:token)
  end

  # A same-origin POST: rack-test's default host, named the way a browser names
  # it. Without an Origin at all the Referer check is what has to answer.
  def csrf_env
    { "HTTP_ORIGIN" => "http://example.org" }
  end

  # `accept: :json` sends the header the panel's fetch() sends. It changes
  # nothing — that is the point, and two tests above post `text/html` to prove
  # it — but posting the way the real caller does keeps the default honest.
  def post_write(path, params)
    env = params.delete(:accept) == :json ? csrf_env.merge("HTTP_ACCEPT" => "application/json") : csrf_env
    post path, params.merge(token: token), env
  end

  def json_body
    JSON.parse(last_response.body)
  end
end
