# frozen_string_literal: true

require_relative "search_case"

# What every search engine must do, whichever one it is — the contract that
# replaced "the linear scan is the oracle".
#
# That rule said an addon's results must be "the same match set, modulo ranking
# order" as the kernel's. It cannot survive more than one engine: the index and
# the scan disagree about match sets *by design* — a phrase, an infix, a dotted
# identifier — so naming either one the oracle would make the other a bug. What
# they must agree on is narrower and firmer: the shape of an answer, the meaning
# of ANDed terms, what `fields:` restricts, and how rows are ordered. Anything
# past that is the engine's own semantics, declared as a capability and tested in
# the blocks gated on it.
#
# A new engine earns its conformance by registering and including this module.
# That is the property the old rule was reaching for and could not express.
#
# Usage — note that the `include` must follow `engine_under_test`, because the
# hook reads it to decide which capability-gated blocks to define at all:
#
#   class MyEngineTest < SearchCase
#     def self.engine_under_test
#       OKF::Bundle::Search::Index
#     end
#     include EngineConformance
#   end
module EngineConformance
  def self.included(base)
    engine = base.engine_under_test

    base.class_eval do
      # ── the shape of an answer ────────────────────────────────────────────

      test "a row is the facade's hash, in the facade's key order" do
        rows = search(bundle(concept("a", title: "Dedup key", body: "chosen for retries")), [ "dedup" ])

        assert_equal 1, rows.size
        assert_equal %i[id title type area tags matched score snippet], rows.first.keys,
          "the facade owns the row; an engine that reshaped it would make two engines mean two things"
      end

      test "a single bundle carries no slug, and across labels every row with one" do
        one = bundle(concept("a", title: "Dedup key"))
        refute_includes search(one, [ "dedup" ]).first.keys, :slug,
          "a path-named search has no slug to carry"

        rows = search_across([ [ "left", one ], [ "right", bundle(concept("b", title: "Dedup key")) ] ], [ "dedup" ])
        assert_equal %w[left right], rows.map { |row| row[:slug] }.sort
        assert_equal %i[slug id title type area tags matched score snippet], rows.first.keys
      end

      test "across keeps same-id concepts from different bundles distinct" do
        rows = search_across([
                               [ "left", bundle(concept("shared", title: "Dedup key")) ],
                               [ "right", bundle(concept("shared", title: "Dedup key")) ]
                             ], [ "dedup" ])

        assert_equal 2, rows.size, "a merge that collided two bundles' same-named concepts would drop one silently"
        assert_equal %w[shared shared], rows.map { |row| row[:id] }
        assert_equal %w[left right], rows.map { |row| row[:slug] }.sort
      end

      test "area is the concept's top-level directory, and (root) when it has none" do
        rows = search(bundle(concept("tables/orders", title: "Dedup key"), concept("charter", title: "Dedup key")), [ "dedup" ])

        assert_equal %w[(root) tables], rows.map { |row| row[:area] }.sort
      end

      # ── what the terms mean ───────────────────────────────────────────────

      test "terms are ANDed: every term must hit, though not necessarily the same field" do
        both = concept("a", title: "Dedup key", body: "chosen for idempotent retries")
        rows = search(bundle(both, concept("b", title: "Dedup key"), concept("c", body: "idempotent retries")), %w[dedup idempotent])

        assert_equal [ "a" ], rows.map { |row| row[:id] },
          "one term hitting is not enough; a concept must answer for all of them"
        assert_equal %w[title body], rows.first[:matched], "and the row says where each landed"
      end

      test "every hit credits at least one real field, in the facade's weight order" do
        rows = search(bundle(concept("dedup/key", title: "Dedup key", type: "Dedup", tags: [ "dedup" ], description: "dedup", body: "dedup")), [ "dedup" ])

        matched = rows.first[:matched]
        refute_empty matched, "a match nobody can explain is a relevance number pretending to be a result"
        assert_empty matched - OKF::Bundle::Search::FIELDS, "an engine cannot credit a field the facade does not search"
        assert_equal OKF::Bundle::Search::FIELDS & matched, matched, "matched fields read strongest-signal first"
      end

      test "fields: restricts both what can match and what can be credited" do
        titled = concept("a", title: "Dedup key", body: "dedup again")
        bodied = concept("b", body: "dedup only here")

        rows = search(bundle(titled, bodied), [ "dedup" ], fields: [ "title" ])

        assert_equal [ "a" ], rows.map { |row| row[:id] }, "a field the caller excluded cannot match"
        assert_equal [ "title" ], rows.first[:matched], "nor be credited when another field also hit"
      end

      # ── ordering ──────────────────────────────────────────────────────────

      test "rows are ordered by score descending, then slug, then id" do
        rows = search_across([
                               [ "b", bundle(concept("second", title: "Dedup key"), concept("first", title: "Dedup key")) ],
                               [ "a", bundle(concept("third", title: "Dedup key")) ]
                             ], [ "dedup" ])

        assert_operator rows.size, :>=, 3
        keys = rows.map { |row| [ -row[:score], row[:slug].to_s, row[:id] ] }
        assert_equal keys.sort, keys, "the facade sorts; an engine's own order never reaches the caller"
      end

      test "a stronger field outranks a weaker one" do
        rows = search(bundle(concept("mentions", body: "billing is mentioned once"), concept("named", title: "Billing")), [ "billing" ])

        assert_equal %w[named mentions], rows.map { |row| row[:id] },
          "every engine weighs a title hit above a body hit, however it computes the number"
      end

      # ── snippets ──────────────────────────────────────────────────────────

      test "a body hit carries a bounded window; a title hit needs none" do
        long = "padding text " * 40
        rows = search(bundle(concept("buried", body: "#{long} dedup #{long}"), concept("titled", title: "Dedup key")), [ "dedup" ])

        buried = rows.find { |row| row[:id] == "buried" }
        assert_includes buried[:snippet], "dedup", "the window opens on the term that hit"
        assert_operator buried[:snippet].length, :<, 200, "a snippet is a window, not the body"
        assert_equal "", rows.find { |row| row[:id] == "titled" }[:snippet],
          "a title hit already shows on the row, so there is no context left to buy"
      end

      # ── the empty answers ─────────────────────────────────────────────────

      test "no terms, blank terms, and no hits each answer with no rows" do
        one = bundle(concept("a", title: "Dedup key"))

        assert_equal [], search(one, [])
        assert_equal [], search(one, [ "  ", nil ]), "blank terms are dropped, and dropping them all means no query"
        assert_equal [], search(one, [ "nothing-says-this" ])
        assert_equal [], search_across([ [ "left", OKF::Bundle.new(concepts: []) ] ], [ "dedup" ])
      end

      # ── capability-gated: only for engines that declare it ────────────────

      if engine.capabilities.include?(:regexp)
        test "regexp: a pattern is matched against raw text" do
          rows = search(bundle(concept("a", body: "raised err_billing_409 downstream")), [ "err_[a-z]+_409" ], regexp: true)

          assert_equal [ "a" ], rows.map { |row| row[:id] }
        end

        test "regexp: a pattern reaches the mid-word fragments a token index cannot" do
          rows = search(bundle(concept("a", title: "Customers")), [ "ustomer" ], regexp: true)

          assert_equal [ "a" ], rows.map { |row| row[:id] }
        end

        test "regexp: an invalid pattern raises, so the caller can call it a usage error" do
          assert_raises(RegexpError) { search(bundle(concept("a", title: "Anything")), [ "[unclosed" ], regexp: true) }
        end
      end

      if engine.capabilities.include?(:fuzzy)
        test "fuzzy: a typo within the edit distance still matches, and exact-by-default does not" do
          one = bundle(concept("a", title: "Customers"))

          assert_equal [], search(one, [ "custommer" ]), "exact by default — the agent is the fuzzy layer until it asks not to be"
          assert_equal [ "a" ], search(one, [ "custommer" ], fuzzy: true).map { |row| row[:id] }
        end
      end

      if engine.capabilities.include?(:prefix)
        test "prefix: a term matches the tokens it prefixes" do
          rows = search(bundle(concept("a", title: "Deduplication")), [ "dedup" ])

          assert_equal [ "a" ], rows.map { |row| row[:id] }
        end
      end
    end
  end

  private

  def engine
    self.class.engine_under_test
  end

  # Every conformance case goes through the facade with the registry overridden,
  # because the contract under test is what a *caller* gets — the row, the order,
  # the snippet — not what the engine returns to the facade.
  def search(bundle, terms, fields: nil, regexp: false, fuzzy: false)
    OKF::Bundle::Search.call(bundle, terms, fields: fields, regexp: regexp, fuzzy: fuzzy, engines: [ engine ])
  end

  def search_across(bundles, terms)
    OKF::Bundle::Search.across(bundles, terms, engines: [ engine ])
  end
end
