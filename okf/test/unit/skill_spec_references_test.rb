# frozen_string_literal: true

require "test_helper"
require "okf"

# Every SPEC section the skill cites must exist in the vendored SPEC.md — the
# mechanical check the v0.1→v0.2 renumbering demanded. A spot-check cannot fail;
# this can: v0.1's §5.3 (broken links) became v0.2's §6.1, while §6.3 is the
# references/ convention — a mechanical §5→§6 rewrite lands on a plausible,
# wrong section and no reader notices.
class OKF::SkillSpecReferencesTest < OKF::TestCase
  SKILL_ROOT = File.expand_path("../../lib/okf/skill", __dir__)

  test "every §n(.n) cited by the skill names a heading the vendored SPEC actually has" do
    spec = File.read(File.join(SKILL_ROOT, "reference", "SPEC.md"))
    headings = spec.scan(/^\#{2,3}\s+(\d+(?:\.\d+)?)[.\s]/).flatten.to_set

    offenders = []
    Dir.glob(File.join(SKILL_ROOT, "**", "*.md")).each do |path|
      next if File.basename(path) == "SPEC.md"

      File.read(path).scan(/§(\d+(?:\.\d+)?)/) do |(section)|
        offenders << "#{path.sub("#{SKILL_ROOT}/", "")}: §#{section}" unless headings.include?(section)
      end
    end

    assert_empty offenders, "cited but not a SPEC heading — a renumbering artifact"
  end

  test "the vendored SPEC is v0.2 and no skill file still declares 0.1" do
    spec = File.read(File.join(SKILL_ROOT, "reference", "SPEC.md"))
    assert_includes spec, "**Version 0.2**"

    stale = Dir.glob(File.join(SKILL_ROOT, "**", "*.md")).select do |path|
      File.read(path).include?(%(okf_version: "0.1"))
    end
    assert_empty stale.map { |path| path.sub("#{SKILL_ROOT}/", "") }
  end

  test "no template or instruction writes the retired timestamp field" do
    writers = Dir.glob(File.join(SKILL_ROOT, "**", "*.md")).select do |path|
      next false if File.basename(path) == "SPEC.md"

      File.read(path).match?(/^timestamp:/)
    end
    assert_empty writers.map { |path| path.sub("#{SKILL_ROOT}/", "") },
      "the skill may explain the legacy fallback but never writes the retired spelling"
  end
end
