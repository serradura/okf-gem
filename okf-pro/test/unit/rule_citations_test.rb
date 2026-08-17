# frozen_string_literal: true

require "test_helper"

# A refusal cites the rule it enforces — "RULE 3 — 6 in flight against a cap of
# 5" — and that citation is the only route from the message to the paragraph
# explaining it. The agent reads the refusal, looks the rule up in the skill,
# and acts. So the word and the number in the message have to match a heading
# in the skill that actually ships.
#
# `reconcile-search` cited "LAW 1" while the skill's heading is "Rule 1", so the
# one gate whose whole job is to make somebody go and read something pointed at
# a heading that does not exist. Nothing failed: the refusal still refused, and
# the search for it just came back empty — which reads as the agent's fault.
#
# The design bundle calls these three the *laws*, deliberately, because that is
# the register a maintainer argues them in. The skill calls them *rules*,
# because that is the register an agent obeys them in. This pins the boundary:
# whatever the design record says, what a refusal cites is what the skill
# teaches.
class RuleCitationsTest < OKF::Pro::TestCase
  SOURCES = Dir[File.expand_path("../../lib/okf/pro/*.rb", __dir__)].freeze

  # "RULE 3 — ", "Rule 3, dormancy — ": the word, then the number.
  CITATION = /\b(LAW|Law|RULE|Rule) (\d+)\b/.freeze

  # Comment lines are dropped, and that boundary is the point rather than a
  # convenience. A comment is the maintainer's register, where "Law 2" is the
  # right word because the design bundle argues these as laws. A string is the
  # agent's, where the only word that resolves is the one the skill's heading
  # uses. Same three ideas, two audiences, and only one of them can follow a
  # citation to a heading.
  def citations
    SOURCES.flat_map do |path|
      prose = OKF::Pro.read_text(path).each_line.grep_v(/\A\s*#/).join
      prose.scan(CITATION).map { |word, number| [ word, number.to_i, File.basename(path) ] }
    end
  end

  test "every rule a refusal cites is a heading the shipped skill carries" do
    headings = skill_text.scan(/^#+ Rule (\d+)/).flatten.map(&:to_i)

    refute_empty headings, "the skill states no numbered rules — if the headings changed, " \
                           "change this pattern with them rather than deleting the pin"

    citations.each do |word, number, file|
      assert_includes headings, number,
        "#{file} cites #{word} #{number}, and the skill has no `## Rule #{number}` to look up"
    end
  end

  test "a refusal says rule, because that is the word the skill's headings use" do
    offenders = citations.reject { |word, _, _| word.casecmp("RULE").zero? }
                         .map { |word, number, file| "#{file}: #{word} #{number}" }

    assert_empty offenders,
      "the skill teaches `## Rule N`, so a refusal citing anything else sends the reader " \
      "looking for a heading that is not there"
  end
end
