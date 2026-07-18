# frozen_string_literal: true

require_relative "search_case"

# Can the index still find what is written in the bundle?
#
# The conformance suite proves the engines agree about the *shape* of an answer —
# row keys, ordering, AND semantics. It cannot notice that both of them are
# missing a third of the matches, and that blind spot is not hypothetical: the
# index swap silently made every word inside a code span unfindable, and the
# release notes recorded only the infix loss because that analysis reasoned about
# the tokenizer instead of running queries against a corpus.
#
# This file runs the queries. It measures the index against the scan, which earns
# the role of oracle for *recall* specifically — not for ranking, and not for
# match sets, where the two engines disagree by design (see
# accepted_losses_test.rb). The scan matches raw text literally, so a word that
# is present is a word it finds. Anything the index cannot find that the scan can
# is recall lost to tokenization.
#
# The corpus below is one concept per tokenization hazard. When a new hazard
# appears, the generative test names it rather than waiting for someone to
# notice it in production.
class SearchRecallTest < SearchCase
  Search = OKF::Bundle::Search

  # Written the way documentation actually writes things: code spans, versions,
  # snake and kebab identifiers, flags, a URL, a shell variable, a bracketed tag.
  CORPUS = {
    "spans" => "The `minifts` port and the `json_for_script` helper are wired in.",
    "version" => "Pinned to 7.2.0 exactly, and the v1.8.0 tag followed.",
    "ident" => "Joined on customer_id and okf_stale_after downstream.",
    "flags" => "Pass --stale-after or -e to widen it.",
    "phrase" => "The dedup key is chosen for retries.",
    "hyphen" => "A core-shell split, enforced end-to-end.",
    "url" => "See https://okfgem.com/spec for the source.",
    "env" => "Point $OKF_HOME at a scratch dir.",
    "bracket" => "Status: [draft] pending review.",
    "plain" => "Ordinary prose with unremarkable words like retrieval and conformance."
  }.freeze

  # Every standalone run of word characters in the corpus — what a reader would
  # plausibly type after seeing it written.
  WORD = /\p{Alnum}[\p{Alnum}_.\-\/]*\p{Alnum}/.freeze

  # The words the index cannot find, and why. Every one is glued to a Unicode
  # *symbol* rather than punctuation: MiniSearch splits on `\p{Z}\p{P}`, and a
  # backtick is `Sk` while `$` is `Sc`, so neither is ever split off. The token
  # stored is "`minifts`", which the query `minifts` does not match.
  #
  # This list is a statement of a known defect, not a target. It shrinks when the
  # tokenizer learns to strip symbol edges; it must never grow silently.
  KNOWN_HOLES = %w[minifts json_for_script OKF_HOME].freeze

  def corpus
    bundle(*CORPUS.map { |id, body| concept(id, body: body) })
  end

  def words
    CORPUS.values.flat_map { |body| body.scan(WORD) }.uniq
  end

  def findable?(word, engine: nil)
    Search.call(corpus, [ word ], engine: engine).size.positive?
  end

  test "the scan finds every word the corpus literally contains — the oracle is sound" do
    # If this ever fails, the measurement below is meaningless: it would mean the
    # baseline the index is compared against has holes of its own.
    missed = words.reject { |word| findable?(word, engine: "scan") }

    assert_empty missed, "raw-text matching cannot miss a word that is present"
  end

  test "the index's recall holes are exactly the ones we know about" do
    holes = words.reject { |word| findable?(word) }

    assert_equal KNOWN_HOLES.sort, holes.sort,
      "a word the index cannot find and this list does not name is a new tokenization hazard"
  end

  test "every hole is a word glued to a symbol, which is the whole diagnosis" do
    # Keeps KNOWN_HOLES from decaying into a magic list: each entry has to be
    # explainable by the rule, so a hole that appears for some *other* reason
    # fails here even if someone adds it to the list above.
    KNOWN_HOLES.each do |hole|
      glued = CORPUS.values.any? { |body| body =~ /\p{S}#{Regexp.escape(hole)}|#{Regexp.escape(hole)}\p{S}/ }

      assert glued, "#{hole} is unfindable for a reason this file does not explain"
    end
  end

  test "punctuation is split, so an identifier stays findable by its parts" do
    # The other half of the tokenizer's behaviour, and the reason the fix is
    # "strip symbol edges" rather than "stop splitting": `\p{P}` splitting is what
    # makes customer_id reachable as customer, and it is working as intended.
    assert findable?("customer_id"), "the whole identifier"
    assert findable?("customer"), "and either part of it"
    assert findable?("core-shell")
  end

  # -- the other direction: tokenization also costs precision --

  test "splitting on punctuation makes some terms match more than was asked" do
    # Recall's mirror image, pinned in the same place because it drifts with the
    # same change. `stale-after` is two tokens ANDed, so it also finds the concept
    # that says okf_stale_after — the scan, matching raw text, finds only the flag.
    assert_equal 2, Search.call(corpus, [ "stale-after" ]).size,
      "the index reads it as `stale` AND `after`, wherever they fall"
    assert_equal 1, Search.call(corpus, [ "stale-after" ], engine: "scan").size,
      "--engine scan is the recovery, as it is for the recall holes"
  end
end
