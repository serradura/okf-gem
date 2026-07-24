# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::SearchTest < OKF::TestCase
  test "matches are ranked by field weight, strongest first" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("notes/aside", type: "Note", body: "mentions billing once"),
                               concept("services/billing", type: "Service", title: "Billing"),
                               concept("notes/tagged", type: "Note", tags: [ "billing" ])
                             ])

    rows = OKF::Bundle::Search.call(bundle, [ "billing" ])

    assert_equal %w[services/billing notes/tagged notes/aside], rows.map { |row| row[:id] }
    assert_operator rows.first[:score], :>, rows.last[:score]
  end

  test "terms are ANDed: every term must hit, fields may differ" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("a", title: "Dedup key", body: "chosen for idempotent retries"),
                               concept("b", title: "Dedup key"),
                               concept("c", body: "idempotent retries")
                             ])

    rows = OKF::Bundle::Search.call(bundle, %w[dedup idempotent])

    assert_equal [ "a" ], rows.map { |row| row[:id] }
    assert_equal %w[title body], rows.first[:matched]
  end

  test "matching is case-insensitive but the snippet keeps the original case" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("a", body: "The Dedup Key lives in billing.")
                             ])

    rows = OKF::Bundle::Search.call(bundle, [ "dedup key" ])

    assert_equal 1, rows.size
    assert_includes rows.first[:snippet], "Dedup Key"
  end

  test "the snippet is a bounded window with ellipses on the cut sides" do
    body = "#{"x" * 200} needle #{"y" * 200}"
    bundle = OKF::Bundle.new(concepts: [ concept("a", body: body) ])

    rows = OKF::Bundle::Search.call(bundle, [ "needle" ])
    snippet = rows.first[:snippet]

    assert_operator snippet.length, :<=, "needle".length + (2 * OKF::Bundle::Search::SNIPPET_RADIUS) + 2
    assert snippet.start_with?("…"), "left cut carries an ellipsis"
    assert snippet.end_with?("…"), "right cut carries an ellipsis"
    assert_includes snippet, "needle"
  end

  test "a match needing no context has an empty snippet" do
    bundle = OKF::Bundle.new(concepts: [ concept("a", title: "Billing") ])

    rows = OKF::Bundle::Search.call(bundle, [ "billing" ])

    assert_equal "", rows.first[:snippet]
  end

  test "fields: restricts where terms may hit" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("services/billing", title: "Billing"),
                               concept("notes/aside", body: "billing appears here only")
                             ])

    rows = OKF::Bundle::Search.call(bundle, [ "billing" ], fields: [ "body" ])

    assert_equal [ "notes/aside" ], rows.map { |row| row[:id] }
  end

  test "tags match against the space-joined list and rows carry catalog identity" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("services/billing", type: "Service", title: "Billing", tags: %w[payments core])
                             ])

    rows = OKF::Bundle::Search.call(bundle, [ "payments" ])
    row = rows.first

    assert_equal "services/billing", row[:id]
    assert_equal "services", row[:top_dir]
    assert_equal %w[payments core], row[:tags]
    assert_equal [ "tags" ], row[:matched]
  end

  test "a root concept lives in the (root) top-level dir" do
    bundle = OKF::Bundle.new(concepts: [ concept("mission", title: "Mission") ])

    rows = OKF::Bundle::Search.call(bundle, [ "mission" ])

    assert_equal "(root)", rows.first[:top_dir]
  end

  test "no terms, blank terms, or no hits mean no rows" do
    bundle = OKF::Bundle.new(concepts: [ concept("a", title: "Billing") ])

    assert_empty OKF::Bundle::Search.call(bundle, [])
    assert_empty OKF::Bundle::Search.call(bundle, [ "", " " ])
    assert_empty OKF::Bundle::Search.call(bundle, [ "absent" ])
  end

  test "terms match whole tokens and their prefixes, but never an infix" do
    bundle = OKF::Bundle.new(concepts: [ concept("a", body: "we rely on deduplication here") ])

    assert_equal [ "a" ], OKF::Bundle::Search.call(bundle, [ "deduplication" ], engine: "index").map { |row| row[:id] }
    assert_equal [ "a" ], OKF::Bundle::Search.call(bundle, [ "dedup" ], engine: "index").map { |row| row[:id] },
      "a term reaches the token it prefixes"
    assert_empty OKF::Bundle::Search.call(bundle, [ "duplication" ], engine: "index"),
      "an infix is the recall a token index gives up — the default scan still finds it"
  end

  test "fuzzy: true forgives a typo the exact search misses" do
    bundle = OKF::Bundle.new(concepts: [ concept("a", title: "Customers") ])

    assert_empty OKF::Bundle::Search.call(bundle, [ "custommer" ])
    assert_equal [ "a" ], OKF::Bundle::Search.call(bundle, [ "custommer" ], fuzzy: true).map { |row| row[:id] }
  end

  test "across labels each row with its bundle and ranks them in one corpus" do
    one = OKF::Bundle.new(concepts: [ concept("shared", title: "Billing", body: "invoices and dunning") ])
    two = OKF::Bundle.new(concepts: [ concept("shared", body: "billing is mentioned once") ])

    rows = OKF::Bundle::Search.across([ [ "one", one ], [ "two", two ] ], [ "billing" ])

    assert_equal %w[one two], rows.map { |row| row[:slug] },
      "ids collide across bundles, so the slug is what keeps the two rows apart"
    assert_equal %w[shared shared], rows.map { |row| row[:id] }
    assert_operator rows.first[:score], :>, rows.last[:score]
  end

  test "a single-bundle row carries no slug key at all" do
    bundle = OKF::Bundle.new(concepts: [ concept("a", title: "Billing") ])

    refute OKF::Bundle::Search.call(bundle, [ "billing" ]).first.key?(:slug),
      "one bundle has no slug to carry, and a nil label would project as a real field"
  end

  test "regexp: true treats terms as case-insensitive Ruby patterns" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("a", body: "raises ERR_DEDUP_409 on conflict"),
                               concept("b", body: "raises ERR_RATE_429 under load")
                             ])

    rows = OKF::Bundle::Search.call(bundle, [ "err_[a-z]+_409" ], regexp: true)

    assert_equal [ "a" ], rows.map { |row| row[:id] }
    assert_includes rows.first[:snippet], "ERR_DEDUP_409"
  end

  test "an invalid pattern raises RegexpError for the caller to translate" do
    bundle = OKF::Bundle.new(concepts: [ concept("a") ])

    assert_raises(RegexpError) { OKF::Bundle::Search.call(bundle, [ "[unclosed" ], regexp: true) }
  end

  test "score ties order by id" do
    bundle = OKF::Bundle.new(concepts: [
                               concept("b", body: "needle"),
                               concept("a", body: "needle")
                             ])

    rows = OKF::Bundle::Search.call(bundle, [ "needle" ])

    assert_equal %w[a b], rows.map { |row| row[:id] }
  end

  private

  def concept(path, type: "Note", title: nil, description: nil, tags: nil, body: "")
    frontmatter = { "type" => type }
    frontmatter["title"] = title if title
    frontmatter["description"] = description if description
    frontmatter["tags"] = tags if tags
    OKF::Concept.new(path: "#{path}.md", frontmatter: frontmatter, body: body)
  end
end
