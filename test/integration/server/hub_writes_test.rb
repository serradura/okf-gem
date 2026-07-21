# frozen_string_literal: true

require "test_helper"

require "json"
require "rack/test"

require "okf"
require "okf/registry"
require "okf/server/hub"

# The server's first state-changing requests: the manager's default / rename /
# remove / add, POSTed from plain forms. Three things have to hold on every one
# of them, and each has cost somebody a bad afternoon somewhere:
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

    assert_equal 303, last_response.status
    assert_equal "/b/", last_response.headers["location"].split("?").first
    assert_equal %w[beta alpha], reloaded.slugs, "the file is the record"

    get "/"
    assert_equal "/b/beta/", last_response.headers["location"], "and the running hub opens the new default"
  end

  test "rename gives the entry a new slug and a new mount" do
    post_write("/registry/rename", slug: "alpha", to: "handbook")

    assert_equal 303, last_response.status
    assert_includes reloaded.slugs, "handbook"

    get "/b/handbook/"
    assert_equal 200, last_response.status, "the new mount answers without a restart"

    get "/b/alpha/"
    assert_equal 404, last_response.status, "and the old one stops answering"
  end

  test "remove drops the entry and leaves the directory alone" do
    dir = File.join(@root, "beta")

    post_write("/registry/remove", slug: "beta")

    assert_equal 303, last_response.status
    assert_equal %w[alpha], reloaded.slugs
    assert File.directory?(dir), "removing a reference never deletes the bundle"

    get "/b/beta/"
    assert_equal 404, last_response.status
  end

  test "add registers a directory by path and mounts it live" do
    make_bundle("gamma")

    post_write("/registry/add", path: File.join(@root, "gamma"))

    assert_equal 303, last_response.status
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

  test "a read-only hub refuses every write and shows no controls" do
    boot("alpha", "beta", writable: false)

    get "/b/"
    refute_includes last_response.body, "<form", "a control nobody may use is not offered"

    post_write("/registry/remove", slug: "beta")
    assert_equal 403, last_response.status
    assert_equal %w[alpha beta], reloaded.slugs
  end

  test "an ephemeral hub has no registry to write to" do
    @app = OKF::Server::Hub.new([ hosted("alpha") ], writable: true)

    post "/registry/remove", { slug: "alpha", token: "any" }, csrf_env
    assert_equal 409, last_response.status
  end

  # ── the same verbs, answered as JSON ──────────────────────────────────────
  #
  # The /b/ manager is a document: it posts a form and gets a page back. The
  # graph page's Bundles panel is not — it stays where it is and re-reads the
  # list. So a request that says it wants JSON gets the outcome as data, and
  # every guard, every message and every exit code stays exactly the same. Two
  # answers to one question, never two decisions.

  test "an Accept: application/json write answers with the outcome, not a redirect" do
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
    assert_includes json_body["error"], "--allow-manage"
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

  # ── the page the forms live on ────────────────────────────────────────────

  test "the manager offers one form per action, each carrying the token" do
    get "/b/"

    assert_includes last_response.body, %(action="/registry/default")
    assert_includes last_response.body, %(action="/registry/rename")
    assert_includes last_response.body, %(action="/registry/remove")
    assert_includes last_response.body, %(action="/registry/add")
    assert_equal last_response.body.scan('name="token"').length,
      last_response.body.scan("<form").length, "every form is guarded, not just the first"
  end

  test "the default row offers no make-default button, since it already is" do
    get "/b/"

    forms = last_response.body.scan(%r{<form[^>]*registry/default.*?</form>}m)
    assert_equal 1, forms.length, "two bundles, one of them already default"
  end

  test "a write redirects back to the manager, which reports what happened" do
    post_write("/registry/rename", slug: "alpha", to: "handbook")
    follow_redirect!

    assert_equal 200, last_response.status
    assert_includes last_response.body, "handbook"
    assert_match(/class="flash/, last_response.body)
  end

  test "under a mounted prefix the forms and the redirect stay inside it" do
    get "/b/", {}, "SCRIPT_NAME" => "/kb"
    assert_includes last_response.body, %(action="/kb/registry/rename")

    post "/registry/rename", { slug: "alpha", to: "handbook", token: token },
      csrf_env.merge("SCRIPT_NAME" => "/kb")
    assert_equal "/kb/b/", last_response.headers["location"].split("?").first
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

  # The page's own token, read back off the manager the way a browser would.
  def token
    get "/b/"
    last_response.body[/name="token" value="([^"]+)"/, 1]
  end

  # A same-origin POST: rack-test's default host, named the way a browser names
  # it. Without an Origin at all the Referer check is what has to answer.
  def csrf_env
    { "HTTP_ORIGIN" => "http://example.org" }
  end

  # `accept: :json` asks for the panel's answer shape; without it this is the
  # manager's own form post, and both go through the identical guards.
  def post_write(path, params)
    env = params.delete(:accept) == :json ? csrf_env.merge("HTTP_ACCEPT" => "application/json") : csrf_env
    post path, params.merge(token: token), env
  end

  def json_body
    JSON.parse(last_response.body)
  end
end
