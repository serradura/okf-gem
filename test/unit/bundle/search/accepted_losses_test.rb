# frozen_string_literal: true

require_relative "search_case"

# The precision the token index gives up, pinned from both sides.
#
# Swapping the linear scan for a BM25+ index bought ranking, prefix matching and
# opt-in fuzziness. It cost exactness: a phrase stops being contiguous, and a
# dotted or underscored identifier shatters into its parts. Ranking mitigates the
# damage — in every probe the true hit still came first — so what is lost is
# precision, not the answer. But "mitigated" is not "absent", and an unpinned
# tradeoff is indistinguishable from a bug nobody has noticed yet.
#
# Each test therefore asserts BOTH sides: the false positive the index now admits,
# **and** that -e still refuses it. Asserting only that the right concept matches
# is what let the phrase regression ship green — every one of these queries still
# finds its true hit, which is exactly why the exclusion is the assertion that
# carries the weight.
#
# Writing these also falsified the mitigation they were meant to record: the true
# hit does *not* reliably rank first. See the last test.
class SearchAcceptedLossesTest < SearchCase
  Search = OKF::Bundle::Search

  test "a phrase is two tokens: the index matches them paragraphs apart, -e demands them adjacent" do
    adjacent = concept("adjacent", body: "the dedup key is chosen so retries are idempotent")
    apart = concept("apart", body: "dedup is documented elsewhere. The partition key is not.")

    loose = Search.call(bundle(adjacent, apart), [ "dedup key" ])
    assert_equal %w[adjacent apart], loose.map { |row| row[:id] }.sort,
      "one argument is still two tokens, ANDed wherever they fall — the phrase is not preserved"

    exact = Search.call(bundle(adjacent, apart), [ "dedup key" ], regexp: true)
    assert_equal [ "adjacent" ], exact.map { |row| row[:id] },
      "-e matches raw text, so the words must actually be next to each other"
  end

  test "a dotted version shatters into its numbers, and -e keeps it whole" do
    pinned = concept("pinned", body: "pinned to MiniSearch 7.2.0 so both engines rank alike")
    decoy = concept("decoy", body: "0 downtime across 7 regions and 2 availability zones")

    loose = Search.call(bundle(pinned, decoy), [ "7.2.0" ])
    assert_includes loose.map { |row| row[:id] }, "decoy",
      "the index sees the tokens 7, 2 and 0, which a sentence of unrelated numbers satisfies"

    exact = Search.call(bundle(pinned, decoy), [ "7.2.0" ], regexp: true)
    assert_equal [ "pinned" ], exact.map { |row| row[:id] }
  end

  test "an underscored identifier splits on the underscore, and -e keeps it whole" do
    orders = concept("orders", body: "the orders table keys on customer_id")
    decoy = concept("decoy", body: "the customer table has an id column")

    loose = Search.call(bundle(orders, decoy), [ "customer_id" ])
    assert_includes loose.map { |row| row[:id] }, "decoy",
      "an underscore is punctuation to the tokenizer, so customer_id is the terms customer and id"

    exact = Search.call(bundle(orders, decoy), [ "customer_id" ], regexp: true)
    assert_equal [ "orders" ], exact.map { |row| row[:id] }
  end

  test "a mid-word fragment finds nothing in the index, and -e finds it" do
    customers = bundle(concept("customers", title: "Customers"))

    assert_equal [], Search.call(customers, [ "ustomer" ]),
      "an inverted index is keyed by token, so there is no way to look up an infix"
    assert_equal [ "customers" ], Search.call(customers, [ "ustomer" ], regexp: true).map { |row| row[:id] }
  end

  test "ranking mitigates the loss but does not contain it — noise can take first place" do
    # It would be comfortable to say the true hit always leads, so the cost is
    # only extra rows underneath it. That was the original claim for why the
    # tradeoff was acceptable, and it is false. BM25 normalizes by field length,
    # so a short body dense in 7, 2 and 0 outscores the concept that actually
    # says 7.2.0.
    #
    # The live bundle agrees: `okf search .okf 7.2.0` puts design/ruby-floor —
    # a page full of 2.4, 2.6 and 3.x — above capabilities/graph-server, the one
    # concept naming the version. That is the real argument for keeping -e
    # reachable and documented: not "the ranking will save you".
    rows = Search.call(bundle(
      concept("pinned", body: "pinned to MiniSearch 7.2.0 so both engines rank alike"),
      concept("decoy", body: "0 downtime across 7 regions and 2 availability zones")
    ), [ "7.2.0" ])

    refute_equal "pinned", rows.first[:id],
      "if this starts passing, ranking got better and the docs claiming it saves you can be revisited — check first"
  end

  test "the scan matches literally unless a pattern was actually asked for" do
    # `--engine scan` means "match raw text", which is what the linear scan did
    # before the index landed — and that was *substring* matching, not regexp.
    # Compiling every term as a pattern would make `7.2.0` match `7x2y0` and turn
    # a plain term like `a(b` into a usage error, so choosing the engine would
    # quietly change what the terms mean.
    raw = bundle(concept("a", body: "build 7x2y0 shipped"), concept("b", body: "pinned to 7.2.0 exactly"))

    literal = Search.call(raw, [ "7.2.0" ], engines: [ Search::Scan ])
    assert_equal [ "b" ], literal.map { |row| row[:id] }, "a dot is a dot until -e says otherwise"

    pattern = Search.call(raw, [ "7.2.0" ], regexp: true, engines: [ Search::Scan ])
    assert_equal %w[a b], pattern.map { |row| row[:id] }.sort, "-e opts into the pattern reading"
  end

  test "a metacharacter is an ordinary character to a literal scan" do
    # `[draft]` read as a pattern is a character class — it matches any concept
    # containing d, r, a, f or t, which is nearly all of them. Read literally it
    # matches the one that says so.
    tagged = bundle(concept("a", body: "status: [draft] pending review"), concept("b", body: "shipped and stable"))

    rows = Search.call(tagged, [ "[draft]" ], engines: [ Search::Scan ])
    assert_equal [ "a" ], rows.map { |row| row[:id] }, "brackets are characters, not a character class"

    # And an unbalanced construct must not blow up a search nobody asked to be a
    # pattern — that would turn an ordinary term into exit 2.
    unbalanced = Search.call(tagged, [ "review (pending" ], engines: [ Search::Scan ])
    assert_equal [], unbalanced, "an invalid pattern is only invalid when a pattern was requested"
  end

  test "-e is a pattern language, not a literal one — the exactness has an edge" do
    # Worth pinning because the help calls -e "matched against raw text", which a
    # reader can hear as "matched literally". A dot is still any character, so the
    # recovery is exact about *adjacency*, not about the characters themselves.
    rows = Search.call(bundle(concept("a", body: "build 7x2y0 shipped")), [ "7.2.0" ], regexp: true)

    assert_equal [ "a" ], rows.map { |row| row[:id] },
      "someone wanting the literal string wants -e '7\\.2\\.0'"
  end
end
