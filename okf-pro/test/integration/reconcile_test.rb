# frozen_string_literal: true

require "test_helper"

# Rule 1. The gate's reach is bounded by the filename's vocabulary, which is
# the limit the rule states about itself — it catches collisions as well as
# your search words do, and no better. These tests pin the boundary rather
# than pretend it is not there.
class ReconcileTest < OKF::Pro::TestCase
  def bundle_with_terms(b)
    b.concept("glossary/binding-estimate.md", type: "Term",
      body: "# Definition\n\nA binding estimate fixes the price for the listed inventory.\n")
    b.concept("reference/movers-quote.md", type: "Briefing",
      body: "# Summary\n\nThe quote is a binding estimate and cannot change at delivery.\n")
  end

  def test_reports_concepts_that_share_the_vocabulary
    with_bundle do |b|
      bundle_with_terms(b)
      target = OKF::Pro::Target.for(write_event(b.path, "reference/binding-estimate-notes.md"))

      refusal = OKF::Pro::Reconcile.search(target, write_event(b.path, "reference/binding-estimate-notes.md"))

      assert_equal 1, refusal.size
      assert_match(/RULE 1 — reconciliation/, refusal.first)
      assert_match(%r{glossary/binding-estimate}, refusal.first)
      assert_match(%r{reference/movers-quote}, refusal.first)
    end
  end

  def test_says_nothing_when_the_vocabulary_is_new
    with_bundle do |b|
      bundle_with_terms(b)
      e = write_event(b.path, "learnings/kettle-descaling.md")

      assert_empty OKF::Pro::Reconcile.search(OKF::Pro::Target.for(e), e)
    end
  end

  # Editing an existing concept is not the moment a claim enters the corpus.
  # Firing here would make every touch of every file a reconciliation prompt.
  def test_ignores_edits_and_fires_only_on_writes
    with_bundle do |b|
      bundle_with_terms(b)
      e = edit_event(b.path, "reference/binding-estimate-notes.md")

      assert_empty OKF::Pro::Reconcile.search(OKF::Pro::Target.for(e), e)
    end
  end

  def test_a_concept_is_not_its_own_collision
    with_bundle do |b|
      bundle_with_terms(b)
      e = write_event(b.path, "glossary/binding-estimate.md")
      refusal = OKF::Pro::Reconcile.search(OKF::Pro::Target.for(e), e)

      # movers-quote still collides; the file being written must not.
      assert_equal 1, refusal.size
      refute_match(/glossary\/binding-estimate .*·/, refusal.first)
      assert_match(%r{reference/movers-quote}, refusal.first)
    end
  end

  # A hit in README or board.md means they quote a concept, not that they
  # assert against one. A gate that reports the README every time is one
  # people learn to scroll past.
  def test_structural_files_are_not_collisions
    with_bundle do |b|
      bundle_with_terms(b)
      dir = b.path
      File.write(File.join(dir, "README.md"),
        "---\ntype: Overview\ntitle: README\ndescription: x\n---\n\n" \
        "# Readme\n\nMentions a binding estimate at length, twice, binding estimate.\n")
      e = write_event(dir, "learnings/binding-lessons.md")
      refusal = OKF::Pro::Reconcile.search(OKF::Pro::Target.for(e), e)

      refute_empty refusal
      refute_match(/README/, refusal.first)
    end
  end

  def test_structural_files_are_not_reconciled_themselves
    with_bundle do |b|
      bundle_with_terms(b)
      %w[board.md log.md index.md README.md CLAUDE.md].each do |name|
        e = write_event(b.path, name)

        assert_empty OKF::Pro::Reconcile.search(OKF::Pro::Target.for(e), e), "#{name} should not reconcile"
      end
    end
  end

  # A journal entry is a record of a day, not a claim about the world. It
  # cannot contradict anything, so it is exempt.
  def test_journal_entries_are_exempt
    with_bundle do |b|
      bundle_with_terms(b)
      e = write_event(b.path, "journal/2026-08-12.md")

      assert_empty OKF::Pro::Reconcile.search(OKF::Pro::Target.for(e), e)
    end
  end

  def test_terms_drop_stop_words_and_cap_at_four
    with_bundle do |b|
      bundle_with_terms(b)
      target = OKF::Pro::Target.for(write_event(b.path, "learnings/the-cost-of-a-late-and-slow-quote.md"))

      terms = OKF::Pro::Reconcile.terms(target)

      assert_equal 4, terms.size
      refute_includes terms, "the"
      refute_includes terms, "of"
      refute_includes terms, "a"
    end
  end

  def test_a_nil_target_has_no_opinion
    assert_empty OKF::Pro::Reconcile.search(nil, event)
  end

  # §5.4 made operative. The skill teaches `status: deprecated` as the
  # machine-readable half of Rule 1's supersession move, and this is what makes
  # the teaching worth anything: a collision with something already deprecated
  # is a collision somebody already settled, and the reader is told so instead
  # of re-litigating it. It is annotated, not filtered — §5.4 keeps a
  # deprecated concept "for links and history", so it is still a real hit.
  def test_a_deprecated_collision_says_it_was_already_settled
    with_bundle do |b|
      b.concept("glossary/binding-estimate.md", type: "Term", status: "deprecated",
        body: "# Definition\n\nA binding estimate fixes the listed price.\n")
      target = OKF::Pro::Target.for(write_event(b.path, "reference/binding-estimate-notes.md"))

      messages = OKF::Pro::Reconcile.search(target, write_event(b.path, "reference/binding-estimate-notes.md"))

      refute_empty messages
      assert_match(/glossary\/binding-estimate\s+\[deprecated — this collision was already settled\]/, messages.first)
    end
  end

  # And the pin that keeps the annotation from being noise: an ordinary
  # collision carries no marker at all. `status` is absent from almost every
  # concept in a real bundle, and §5.4 makes that mean `stable`.
  def test_an_ordinary_collision_carries_no_marker
    with_bundle do |b|
      b.concept("glossary/binding-estimate.md", type: "Term",
        body: "# Definition\n\nA binding estimate fixes the listed price.\n")
      target = OKF::Pro::Target.for(write_event(b.path, "reference/binding-estimate-notes.md"))

      messages = OKF::Pro::Reconcile.search(target, write_event(b.path, "reference/binding-estimate-notes.md"))

      refute_empty messages
      refute_match(/deprecated/, messages.first)
    end
  end
end
