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

  # A spy engine: answers the duck type, records the keyword options the facade
  # handed it, and returns no hits. It declares no capabilities, so a query that
  # requires nothing routes straight to it.
  def spy(capabilities: [])
    double = engine(:spy, capabilities: capabilities)
    double.instance_variable_set(:@seen, nil)
    double.define_singleton_method(:seen) { @seen }
    double.define_singleton_method(:call) do |_documents, _terms, **options|
      @seen = options
      []
    end
    double
  end

  test "the built-ins register themselves at load, the default first" do
    assert_equal %i[index scan], Search.engines.map(&:id)
  end

  test "the routable vocabulary is the subset a query can actually ask for" do
    # :prefix is declarable but not routable — the index offers it and nothing
    # asks for its absence. Keeping the two lists distinct is what stops a
    # capability nobody selects on from posing as a routing key.
    assert_equal %i[regexp fuzzy], Search::ROUTABLE
    assert_empty Search::ROUTABLE - Search::CAPABILITIES, "every routable capability must be declarable"
    assert_includes Search::CAPABILITIES, :prefix
    refute_includes Search::ROUTABLE, :prefix
  end

  test "an engine is handed only the options its capabilities imply" do
    # The facade used to pass fuzzy: to every engine and rely on the engine to
    # ignore it. Routing makes that harmless today, but "harmless because
    # something else prevents it" is how an option comes to be silently dropped.
    watcher = spy
    Search.call(bundle(concept("a", title: "Anything")), [ "anything" ], engines: [ watcher ])

    assert_equal [ :fields ], watcher.seen.keys, "an engine declaring no capabilities gets no capability options"
  end

  test "an engine declaring :fuzzy is handed fuzzy, and one declaring :regexp is not" do
    fuzzy_capable = spy(capabilities: [ :fuzzy ])
    Search.call(bundle(concept("a", title: "Anything")), [ "anything" ], fuzzy: true, engines: [ fuzzy_capable ])

    assert_equal true, fuzzy_capable.seen[:fuzzy]

    regexp_capable = spy(capabilities: [ :regexp ])
    Search.call(bundle(concept("a", title: "Anything")), [ "anything" ], engines: [ regexp_capable ])

    refute_includes regexp_capable.seen.keys, :fuzzy
  end

  test "engines is a frozen snapshot — a caller cannot grow the registry by mutating it" do
    assert_predicate Search.engines, :frozen?
    # FrozenError only exists from 2.5; it subclasses RuntimeError, which is the
    # name both floors answer to.
    assert_raises(RuntimeError) { Search.engines << engine(:rogue) }
    assert_equal %i[index scan], Search.engines.map(&:id)
  end

  test "a query needing no capability routes to the default engine" do
    assert_equal Search::Scan, Search.engine_for([])
  end

  test "regexp routes to the engine declaring it, not the default" do
    assert_equal Search::Scan, Search.engine_for([ :regexp ])
  end

  test "fuzzy routes to the engine declaring it" do
    assert_equal Search::Index, Search.engine_for([ :fuzzy ])
  end

  test "the default engine leads the preference order even when registered later" do
    # Registration order is the tie-break, so the default must be listed *last*
    # here or the assertion would hold for the wrong reason — first-registered
    # and default-first are the same answer when they are the same engine.
    engines = [ engine(:index, capabilities: [ :fuzzy ]), engine(:scan, capabilities: [ :regexp ]) ]

    assert_equal :scan, Search.engine_for([], engines: engines).id
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

  # ── naming an engine outright ──────────────────────────────────────────

  test "a named engine answers even when the query requires nothing of it" do
    assert_equal Search::Scan, Search.engine_for([], name: "scan"),
      "naming the engine is how a caller reaches semantics the capability flags cannot ask for"
    assert_equal Search::Index, Search.engine_for([], name: "index")
  end

  test "an engine name is matched without regard to case" do
    assert_equal Search::Scan, Search.engine_for([], name: "SCAN")
  end

  test "a named engine that cannot do what was asked names itself and what is missing" do
    error = assert_raises(Search::UnsupportedQuery) { Search.engine_for([ :regexp ], name: "index") }

    assert_equal [ :regexp ], error.missing
    assert_equal :index, error.engine, "the caller named this engine, so the error must name it back"
  end

  test "a name nobody registered is an UnknownEngine carrying what is available" do
    error = assert_raises(Search::UnknownEngine) { Search.engine_for([], name: "fts5") }

    assert_equal "fts5", error.name
    assert_equal %i[index scan], error.available
  end

  test "an unavailable engine cannot be reached by name" do
    engines = [ engine(:broken, capabilities: [], available: false) ]

    error = assert_raises(Search::UnknownEngine) { Search.engine_for([], name: "broken", engines: engines) }

    assert_empty error.available, "an engine whose backing store is missing is not a choice on offer"
  end

  test "the facade forwards a named engine, and the name beats the default" do
    # An infix separates the two engines cleanly: the scan matches raw text so it
    # finds it, the index matches whole tokens so it cannot. With the scan now the
    # default, naming the *index* is what proves the name is honoured — the
    # contrast runs the other way than it did when the index led.
    raw = bundle(concept("a", title: "Customers"))

    assert_equal [], Search.call(raw, [ "ustomer" ], engine: "index"),
      "--engine index is honoured even though the default would have matched"
    assert_equal [ "a" ], Search.call(raw, [ "ustomer" ]).map { |row| row[:id] },
      "the default reaches an infix, which is what naming the index gave up"
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
