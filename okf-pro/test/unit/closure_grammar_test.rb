# frozen_string_literal: true

require "test_helper"

# The closure grammar is enumerated in two places that must never disagree: the
# regex `Pairing::MARKER`, which decides whether a project is closed, and the
# skill's closing ritual, which is where a person or an agent reads what to
# type. `pairing.rb` has claimed for its whole life that "the grammar tests pin
# both lists to each other". They did not. This is that test.
#
# The failure it closes is quiet in the worst way. A spelling the skill teaches
# and the regex rejects leaves the project OPEN: its board lines are still
# demanded, `unpaired_projects` keeps reporting it, and the person who followed
# the instructions exactly is told they did it wrong. A spelling the regex
# accepts and the skill never teaches is the reverse — a project closed by
# accident, its board lines removed by a check nobody asked.
#
# The lists are extracted from the prose rather than restated here, because a
# copy in this file would be a third list to drift.
class ClosureGrammarTest < OKF::Pro::TestCase
  TEMPLATE = File.expand_path("../../lib/okf/pro/template", __dir__)
  PROJECTS_INDEX = File.join(TEMPLATE, "seed", ".okf", "projects", "index.md")

  DATE = /\d{4}-\d{2}-\d{2}/.freeze

  # Every backticked span carrying both the word and a date: what the document
  # tells its reader to type.
  def taught(text)
    text.scan(/`([^`]*)`/).flatten
        .select { |span| span =~ /closed/i && span =~ DATE }
  end

  # Every double-quoted span carrying both: the document's own counter-examples,
  # each of which it says explicitly leaves the project open.
  def refused(text)
    text.scan(/"([^"]*)"/).flatten
        .select { |span| span =~ /closed/i && span =~ DATE }
  end

  # The skill is a directory, so it is read whole: which file teaches the
  # spelling is the skill's business, not this pin's.
  def projects_index_text
    OKF::Pro.read_text(PROJECTS_INDEX)
  end

  # By key, not by prose: the enumeration this pin reads is whichever paragraph
  # carries the marker, wherever the skill has since put it.
  def closure_rule_text
    skill_rule("okf-pro-closure-marker")
  end

  # Both documents teach the spellings — the skill because it is the operative
  # rule, the projects index because it is where a person filing work looks.
  [ [ "the skill", :closure_rule_text ], [ "the projects index the scaffold writes", :projects_index_text ] ].each do |label, source|
    test "every closure spelling #{label} teaches is one MARKER accepts" do
      spellings = taught(send(source))

      refute_empty spellings, "#{label} enumerates no closure spelling at all — the coupling is gone, not satisfied"
      spellings.each do |spelling|
        assert OKF::Pro::Pairing.marker?(spelling),
          "#{label} teaches #{spelling.inspect}, which Pairing::MARKER rejects — a project closed by the " \
          "book stays open, and its board lines keep being demanded."
      end
    end
  end

  # The third direction, and the one that only became testable when a verb
  # started writing the marker. `okf pro close` emits one spelling; if it is
  # not among the ones the skill teaches, an adopter reading the guide and an
  # adopter running the verb produce different files — and if MARKER rejects
  # it, the project the verb just closed is still open, its board lines gone
  # and its pairing finding back.
  test "the marker `okf pro close` writes is one MARKER accepts and one the skill teaches" do
    emitted = OKF::Pro::Writes.closure_marker("# Alpha migration", Date.new(2026, 8, 12))

    assert OKF::Pro::Pairing.marker?(emitted),
      "`okf pro close` writes #{emitted.inspect}, which Pairing::MARKER rejects — the verb closes " \
      "nothing and takes the board lines with it."

    suffix = emitted[/ — closed .*\z/]
    spellings = taught(closure_rule_text)

    assert spellings.any? { |spelling| spelling.end_with?(suffix) },
      "the skill teaches #{spellings.inspect} and the verb writes #{suffix.inspect} — a reader " \
      "following the guide and a reader running the verb would produce different files."
  end

  # Only the skill names the counter-examples, and deliberately: the list of
  # what is NOT a marker is the subtle half, and a second copy of it in the
  # bundle would be the thing that drifts. The projects index points here.
  test "every non-marker the skill names is one MARKER refuses" do
    sentences = refused(closure_rule_text)

    refute_empty sentences, "the skill names no counter-example — half the coupling is untested"
    sentences.each do |sentence|
      refute OKF::Pro::Pairing.marker?(sentence),
        "the skill says #{sentence.inspect} leaves the project open, and Pairing::MARKER closes it — " \
        "a project closed by accident loses its board lines."
    end
  end
end
