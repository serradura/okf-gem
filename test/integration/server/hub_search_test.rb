# frozen_string_literal: true

require "test_helper"

require "json"
require "rack/test"

require "okf"
require "okf/server/hub"

# The hub's cross-bundle search endpoint — the HTTP face of
# OKF::Bundle::Search.across, and the only place in the server that answers
# about every hosted bundle at once. The command palette's "Concepts" group is
# its only client, so the shape asserted here is the shape the page reads.
class OKF::Server::HubSearchTest < OKF::TestCase
  include Rack::Test::Methods

  attr_reader :app

  setup do
    @root = Dir.mktmpdir("okf-hub-search-test")
    orders = bundle("orders", "Orders",
      "dedup" => "The orders table dedups on a natural key.",
      "refunds" => "Refunds reverse a charge.")
    notes = bundle("notes", "Notes", "standup" => "Notes from the weekly gargoyle standup.")
    @app = OKF::Server::Hub.new([ orders, notes ])
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "GET /search ranks concepts across every hosted bundle" do
    get "/search", q: "dedup"

    assert_equal 200, last_response.status
    assert_match %r{application/json}, last_response.content_type

    body = JSON.parse(last_response.body)
    assert_equal "dedup", body["query"]
    assert_equal 1, body["results"].length
    assert_equal 1, body["total"]

    row = body["results"].first
    assert_equal "orders", row["slug"]
    assert_equal "dedup", row["id"]
    assert_equal "Dedup", row["title"]
    assert_equal "Note", row["type"]
    assert_equal "(root)", row["area"]
    assert_includes row["matched"], "body"
    assert_includes row["snippet"], "dedups on a natural key"
    assert_kind_of Numeric, row["score"]
    refute body["truncated"], "three concepts are nowhere near the cap"
  end

  test "a term that lives only in the second bundle comes back slugged to it" do
    get "/search", q: "gargoyle"

    rows = JSON.parse(last_response.body)["results"]
    assert_equal [ "notes" ], rows.map { |row| row["slug"] }
    assert_equal [ "standup" ], rows.map { |row| row["id"] }
  end

  test "terms are ANDed, as the CLI's search already is" do
    get "/search", q: "orders dedups"
    assert_equal 1, JSON.parse(last_response.body)["results"].length

    get "/search", q: "orders gargoyle"
    assert_empty JSON.parse(last_response.body)["results"], "no concept carries both"
  end

  test "a blank or missing q is an empty result, not an error" do
    # The palette fetches as you type, so the empty box is a normal request.
    empty = { "query" => "", "total" => 0, "truncated" => false, "results" => [] }

    get "/search", q: ""
    assert_equal 200, last_response.status
    assert_equal empty, JSON.parse(last_response.body)

    get "/search"
    assert_equal 200, last_response.status
    assert_equal empty, JSON.parse(last_response.body)
  end

  test "an unknown term is an empty result" do
    get "/search", q: "nothinghere"

    assert_equal 200, last_response.status
    assert_empty JSON.parse(last_response.body)["results"]
  end

  test "fuzzy matching forgives a typo, as the TUI and the page's own search do" do
    get "/search", q: "refumds"

    rows = JSON.parse(last_response.body)["results"]
    assert_equal [ "refunds" ], rows.map { |row| row["id"] }
  end

  test "the index engine backs it, so terms match by token and by prefix" do
    # Named, not inferred: the index is what the browser's own MiniSearch is a
    # port of, so a palette hit and an in-page search rank alike. Its tokenizer
    # is what these two assertions actually pin — the scan would match a
    # substring anywhere, and does not rank at all.
    get "/search", q: "refu"
    assert_equal [ "refunds" ], JSON.parse(last_response.body)["results"].map { |row| row["id"] },
      "a prefix grows to the tokens it prefixes"

    get "/search", q: "efund"
    assert_empty JSON.parse(last_response.body)["results"],
      "and a mid-word substring is not a token — the scan would have matched it"
  end

  test "results are capped, and a truncated answer says so" do
    over = OKF::Server::Hub::SEARCH_LIMIT + 5
    concepts = {}
    (1..over).each { |n| concepts["c#{n}"] = "every concept mentions widgets" }
    @app = OKF::Server::Hub.new([ bundle("big", "Big", concepts) ])

    get "/search", q: "widgets"

    body = JSON.parse(last_response.body)
    assert_equal OKF::Server::Hub::SEARCH_LIMIT, body["results"].length
    assert_equal true, body["truncated"], "a silent cap is a lie about coverage"
    assert_equal over, body["total"]
  end

  test "the endpoint answers under a mounted prefix" do
    get "/search", { q: "dedup" }, "SCRIPT_NAME" => "/kb"

    assert_equal 200, last_response.status
    assert_equal 1, JSON.parse(last_response.body)["results"].length
  end

  test "a non-GET method 404s, like every other route here" do
    post "/search", q: "dedup"

    assert_equal 404, last_response.status
  end

  test "each bundle page carries the relative endpoint that reaches it" do
    get "/b/orders/"

    assert_includes last_response.body, %(SEARCH_ENDPOINT="../../search")
  end

  test "an empty hub answers /search with an empty result rather than 404ing" do
    @app = OKF::Server::Hub.new([])

    get "/search", q: "dedup"

    assert_equal 200, last_response.status
    assert_empty JSON.parse(last_response.body)["results"]
  end

  private

  def bundle(slug, title, concepts)
    dir = File.join(@root, slug)
    FileUtils.mkdir_p(dir)
    concepts.each do |id, body|
      File.write(File.join(dir, "#{id}.md"), "---\ntype: Note\ntitle: #{id.capitalize}\n---\n\n#{body}\n")
    end
    OKF::Server::Hub::Bundle.new(slug, OKF::Bundle::Folder.load(dir), title)
  end
end
