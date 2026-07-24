# frozen_string_literal: true

require "test_helper"

require "json"
require "rack/test"

require "okf"
require "okf/registry"
require "okf/server/hub"

# GET /bundles — what the graph page's Bundles panel reads. It is the /b/
# manager's own rows, as JSON, so the panel and the page cannot disagree about
# what is registered, how big it is, or whether it is healthy.
#
# It is fetched rather than baked into every page for one reason: the registry
# is re-read per request, so a rename made in another terminal shows the next
# time the panel is opened. A boot snapshot would go stale and say nothing.
class OKF::Server::HubBundlesTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @root = Dir.mktmpdir("okf-hub-bundles-test")
    @home = File.join(@root, "home")
    FileUtils.mkdir_p(@home)
    boot("alpha", "beta")
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "every registered bundle, with the facts a reader chooses between them by" do
    get "/bundles"

    assert_equal 200, last_response.status
    assert_match %r{application/json}, last_response.content_type
    rows = payload["bundles"]

    assert_equal %w[alpha beta], rows.map { |row| row["slug"] }
    first = rows.first
    assert_equal "Alpha", first["title"]
    assert_equal 2, first["count"]
    assert_equal "ok", first["health"]
    assert_equal "no problems", first["word"], "the word is the message; the colour only echoes it"
    assert_equal true, first["default"]
    assert_equal false, rows.last["default"], "exactly one default, and the panel is told which"
    assert_equal "beta", rows.last["mount"], "the mount is what a link needs, and is not always the slug"
  end

  test "a registry-backed loopback hub says it is writable and has something to write to" do
    get "/bundles"

    assert_equal true, payload["writable"]
    assert_equal true, payload["registry"]
  end

  test "an ephemeral hub is writable and has nothing to write to, which is a different state" do
    # `okf server dir1 dir2` — bundles named on the command line, no registry.
    # The panel says different things for the two, so it is told them separately.
    @app = OKF::Server::Hub.new([ hosted("alpha") ], writable: true)

    get "/bundles"

    assert_equal true, payload["writable"]
    assert_equal false, payload["registry"]
    assert_equal %w[alpha], payload["bundles"].map { |row| row["slug"] },
      "no registry still means a list — it is what the command line named"
  end

  test "a non-loopback hub reports itself read-only, and still reports every fact" do
    boot("alpha", "beta", writable: false)

    get "/bundles"

    assert_equal false, payload["writable"], "the page never decides this — it is told"
    assert_equal 2, payload["bundles"].length, "the list is worth reading either way"
    assert_equal "no problems", payload["bundles"].first["word"]
  end

  test "an entry whose folder is gone is reported, not dropped" do
    # The question this answers is "where did my bundle go?", and only the
    # registry can answer it — the hub could not load the thing.
    registry = OKF::Registry.load(home: @home)
    registry.add(make_bundle("doomed"), as: "doomed")
    FileUtils.rm_rf(File.join(@root, "doomed"))
    @app = OKF::Server::Hub.new([ hosted("alpha"), hosted("beta") ], registry: OKF::Registry.load(home: @home), writable: true)

    get "/bundles"

    gone = payload["bundles"].find { |row| row["slug"] == "doomed" }
    refute_nil gone, "a row the hub cannot serve is still a row"
    assert_nil gone["mount"], "and it links nowhere, because there is nowhere to link"
    assert_equal "missing", gone["health"]
    assert_equal "folder is gone", gone["word"]
  end

  test "an empty registry is an answer, not an error" do
    # Its own home, because the setup's is not empty — and "nothing registered"
    # is the state a fresh install is in, so the panel has to render it.
    empty = File.join(@root, "empty-home")
    FileUtils.mkdir_p(empty)
    @app = OKF::Server::Hub.new([], registry: OKF::Registry.load(home: empty), writable: true)

    get "/bundles"

    assert_equal 200, last_response.status
    assert_equal [], payload["bundles"], "nothing registered is a real state, and the panel has to render it"
  end

  test "the token is not in this answer" do
    # It is baked into the page that may use it, not handed out by a GET. Same
    # origin protects both, but a credential in a listing endpoint is a habit
    # worth not forming.
    get "/bundles"

    refute_includes last_response.body, "token"
  end

  test "only GET answers here" do
    post "/bundles"

    assert_equal 404, last_response.status
  end

  private

  def payload
    JSON.parse(last_response.body)
  end

  def boot(*slugs, **opts)
    registry = OKF::Registry.load(home: @home)
    slugs.each { |slug| registry.add(make_bundle(slug), as: slug) }
    @app = OKF::Server::Hub.new(
      slugs.map { |slug| hosted(slug) },
      registry: OKF::Registry.load(home: @home),
      writable: opts.fetch(:writable, true)
    )
  end

  def hosted(slug)
    OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(File.join(@root, slug)), slug.capitalize)
  end

  def make_bundle(slug)
    dir = File.join(@root, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.md"), "---\ntype: Note\ntitle: A\ndescription: One.\n---\n\nA concept linking to [b](b.md).\n")
    File.write(File.join(dir, "b.md"), "---\ntype: Note\ntitle: B\ndescription: Two.\n---\n\nBack to [a](a.md).\n")
    dir
  end
end
