# frozen_string_literal: true

require_relative "search_case"

# The engine registry and the capability router — the seam okf-sqlite3 plugs
# into. What is tested here is *selection*, not retrieval: given a set of
# registered engines and the capabilities a query needs, which engine answers.
# Retrieval itself is the conformance suite's job.
class SearchRoutingTest < SearchCase
  Search = OKF::Bundle::Search

  # A minimal engine double. It never runs — the router only reads its three
  # class-level predicates — so it stands in for an addon that is not installed.
  def engine(id, capabilities: [], available: true)
    double = Object.new
    double.define_singleton_method(:id) { id }
    double.define_singleton_method(:capabilities) { capabilities }
    double.define_singleton_method(:available?) { available }
    double
  end

  test "the built-ins register themselves at load, the default first" do
    assert_equal %i[index scan], Search.engines.map(&:id)
  end

  test "engines is a frozen snapshot — a caller cannot grow the registry by mutating it" do
    assert_predicate Search.engines, :frozen?
    # FrozenError only exists from 2.5; it subclasses RuntimeError, which is the
    # name both floors answer to.
    assert_raises(RuntimeError) { Search.engines << engine(:rogue) }
    assert_equal %i[index scan], Search.engines.map(&:id)
  end

  test "a query needing no capability routes to the default engine" do
    assert_equal Search::Index, Search.engine_for([])
  end

  test "regexp routes to the engine declaring it, not the default" do
    assert_equal Search::Scan, Search.engine_for([ :regexp ])
  end

  test "fuzzy routes to the engine declaring it" do
    assert_equal Search::Index, Search.engine_for([ :fuzzy ])
  end

  test "the default engine leads the preference order even when registered later" do
    engines = [ engine(:scan, capabilities: [ :regexp ]), engine(:index, capabilities: [ :fuzzy ]) ]

    assert_equal :index, Search.engine_for([], engines: engines).id
  end

  test "an unavailable engine is passed over for one that can answer" do
    engines = [
      engine(:index, capabilities: [ :fuzzy ], available: false),
      engine(:scan, capabilities: [ :regexp ])
    ]

    assert_equal :scan, Search.engine_for([], engines: engines).id
  end

  test "a capability no available engine offers raises UnsupportedQuery" do
    engines = [ engine(:scan, capabilities: [ :regexp ]) ]

    error = assert_raises(Search::UnsupportedQuery) { Search.engine_for([ :fuzzy ], engines: engines) }

    assert_includes error.message, "fuzzy"
    assert_equal [ :fuzzy ], error.missing
  end

  test "the capability is missing when the only engine offering it is unavailable" do
    engines = [ engine(:index, capabilities: [ :fuzzy ], available: false) ]

    assert_raises(Search::UnsupportedQuery) { Search.engine_for([ :fuzzy ], engines: engines) }
  end

  test "an engine must offer every required capability, not merely one of them" do
    engines = [ engine(:half, capabilities: [ :regexp ]), engine(:other, capabilities: [ :fuzzy ]) ]

    assert_raises(Search::UnsupportedQuery) { Search.engine_for(%i[regexp fuzzy], engines: engines) }
  end

  test "an empty registry is an UnsupportedQuery, not a nil engine handed downstream" do
    error = assert_raises(Search::UnsupportedQuery) { Search.engine_for([], engines: []) }

    assert_includes error.message, "no search engine"
  end

  test "register is idempotent by id — a double require does not double the registry" do
    before = Search.engines

    Search.register(Search::Scan)

    assert_equal before, Search.engines
  end

  test "register refuses a capability outside the vocabulary, so a typo cannot go quiet" do
    error = assert_raises(ArgumentError) { Search.register(engine(:typo, capabilities: [ :regex ])) }

    assert_includes error.message, "regex"
    assert_equal %i[index scan], Search.engines.map(&:id), "a refused registration must leave no trace"
  end

  test "the facade routes on the query, reaching the scan for a pattern" do
    rows = Search.call(bundle(concept("a", body: "err_billing_409 raised")), [ "err_[a-z]+_409" ], regexp: true)

    assert_equal [ "a" ], rows.map { |row| row[:id] }
    # By value, not by class: Integer#round(4) returns a Float on the 2.4 floor.
    assert_equal Search::WEIGHTS["body"], rows.first[:score],
      "the scan scores a body-only hit as that field's weight — the index would return BM25+"
  end

  test "the facade's injected engine list reaches the router" do
    only_scan = bundle(concept("a", body: "anything"))

    assert_raises(Search::UnsupportedQuery) do
      Search.call(only_scan, [ "anything" ], fuzzy: true, engines: [ Search::Scan ])
    end
  end
end
